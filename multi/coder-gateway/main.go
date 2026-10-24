// coder-gateway：多用户版门卫服务
//
// 职责：
//   1. 提供登录页，校验 users.db 中的用户名/密码（bcrypt）
//   2. 登录成功后发 session cookie
//   3. 已登录用户的所有请求（含 WebSocket）反向代理到该用户专属的 ttyd 实例
//
// 架构：
//   浏览器 ── coder.thinkers.top ── Caddy(HTTPS) ── 本服务(:8080)
//                                                   └─ ttyd:alice(:7001)
//                                                   └─ ttyd:bob(:7002)
//
// 说明：ttyd 走 WebSocket，因此这里用 httputil.ReverseProxy（原生支持 ws）。
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// ─────────────────────────────────────────────────────────────
// 配置（可用环境变量覆盖，均有默认值）
// ─────────────────────────────────────────────────────────────
var (
	listenAddr = envOr("GATEWAY_ADDR", ":8080")
	usersFile  = envOr("USERS_FILE", "/srv/coder/users.db")
	// session 有效时长
	sessionTTL = 12 * time.Hour
)

// ─────────────────────────────────────────────────────────────
// 用户表结构（与 coder-admin 脚本共用同一份 JSON 文件）
// ─────────────────────────────────────────────────────────────
type User struct {
	Name        string `json:"name"`         // 用户名（即 tmux socket 名 / 目录名）
	DisplayName string `json:"display_name"` // 显示名（可选）
	PasswordHash string `json:"password_hash"` // bcrypt 哈希
	Port        int    `json:"port"`         // 该用户专属 ttyd 内网端口
	Disabled    bool   `json:"disabled"`     // true = 离职已禁用，禁止登录
	ArchivedAt  string `json:"archived_at"`  // 离职归档时间（RFC3339，空=在职）
}

type UsersDB struct {
	Users []User `json:"users"`
}

var (
	dbMu    sync.RWMutex
	usersDB UsersDB
	// sessionID -> username
	sessions   = map[string]session{}
	sessionMu  sync.RWMutex
)

type session struct {
	Username  string
	ExpiresAt time.Time
}

// ─────────────────────────────────────────────────────────────
// 工具函数
// ─────────────────────────────────────────────────────────────
func envOr(k, d string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return d
}

func loadDB() error {
	dbMu.Lock()
	defer dbMu.Unlock()
	data, err := os.ReadFile(usersFile)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, &usersDB)
}

// findUser 返回用户指针（nil 表示不存在）
func findUser(name string) *User {
	for i := range usersDB.Users {
		if usersDB.Users[i].Name == name {
			return &usersDB.Users[i]
		}
	}
	return nil
}

func randomSessionID() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

// ─────────────────────────────────────────────────────────────
// 会话管理
// ─────────────────────────────────────────────────────────────
func createSession(username string) string {
	id := randomSessionID()
	sessionMu.Lock()
	sessions[id] = session{Username: username, ExpiresAt: time.Now().Add(sessionTTL)}
	sessionMu.Unlock()
	return id
}

func getSession(id string) (string, bool) {
	sessionMu.RLock()
	s, ok := sessions[id]
	sessionMu.RUnlock()
	if !ok {
		return "", false
	}
	if time.Now().After(s.ExpiresAt) {
		sessionMu.Lock()
		delete(sessions, id)
		sessionMu.Unlock()
		return "", false
	}
	return s.Username, true
}

func deleteSession(id string) {
	sessionMu.Lock()
	delete(sessions, id)
	sessionMu.Unlock()
}

// ─────────────────────────────────────────────────────────────
// 登录校验
// ─────────────────────────────────────────────────────────────
func verifyLogin(name, pass string) bool {
	dbMu.RLock()
	u := findUser(name)
	dbMu.RUnlock()
	if u == nil || u.Disabled {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(u.PasswordHash), []byte(pass)) == nil
}

// ─────────────────────────────────────────────────────────────
// WebSocket/HTTP 反向代理到用户 ttyd 实例
// ─────────────────────────────────────────────────────────────
func proxyToUser(w http.ResponseWriter, r *http.Request, username string) {
	dbMu.RLock()
	u := findUser(username)
	dbMu.RUnlock()
	if u == nil || u.Disabled {
		http.Error(w, "账号已不可用", http.StatusForbidden)
		return
	}
	target, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", u.Port))
	proxy := httputil.NewSingleHostReverseProxy(target)
	proxy.ServeHTTP(w, r)
}

func main() {
	if err := loadDB(); err != nil {
		log.Printf("⚠️  首次运行可能还没有用户表：%v", err)
	}

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/login", handleLogin)
	http.HandleFunc("/logout", handleLogout)

	log.Printf("coder-gateway 监听 %s", listenAddr)
	log.Fatal(http.ListenAndServe(listenAddr, nil))
}

// handleRoot：未登录显示登录页；已登录反代到用户 ttyd
func handleRoot(w http.ResponseWriter, r *http.Request) {
	// 从 cookie 取 session
	username := ""
	if c, err := r.Cookie("coder_session"); err == nil {
		if u, ok := getSession(c.Value); ok {
			username = u
		}
	}

	if username == "" {
		serveLoginPage(w, r)
		return
	}
	proxyToUser(w, r, username)
}

func handleLogin(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
		return
	}
	if err := r.ParseForm(); err != nil {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}
	name := strings.TrimSpace(r.FormValue("username"))
	pass := r.FormValue("password")

	if !verifyLogin(name, pass) {
		// 登录失败，重显登录页并带错误提示
		serveLoginPage(w, r)
		return
	}

	id := createSession(name)
	http.SetCookie(w, &http.Cookie{
		Name:     "coder_session",
		Value:    id,
		Path:     "/",
		HttpOnly: true,
		Expires:  time.Now().Add(sessionTTL),
	})
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	if c, err := r.Cookie("coder_session"); err == nil {
		deleteSession(c.Value)
	}
	http.SetCookie(w, &http.Cookie{
		Name:   "coder_session",
		Value:  "",
		Path:   "/",
		MaxAge: -1,
	})
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

// serveLoginPage：极简登录页
func serveLoginPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	_, _ = io.WriteString(w, `<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>登录</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body{font-family:system-ui;background:#111;color:#eee;display:flex;align-items:center;justify-content:center;height:100vh;margin:0}
  form{background:#1c1c1c;padding:32px;border-radius:12px;width:280px}
  h1{font-size:20px;margin:0 0 20px}
  input{width:100%;box-sizing:border-box;margin:8px 0;padding:10px;border:1px solid #333;border-radius:6px;background:#222;color:#eee}
  button{width:100%;padding:10px;margin-top:12px;background:#4a80ff;color:#fff;border:none;border-radius:6px;cursor:pointer;font-size:15px}
  button:hover{background:#3a6de0}
</style></head><body>
<form method="post" action="/login">
  <h1>AI 编码平台登录</h1>
  <input name="username" placeholder="用户名" autocomplete="username" required>
  <input name="password" type="password" placeholder="密码" autocomplete="current-password" required>
  <button type="submit">登录</button>
</form>
</body></html>`)
}
