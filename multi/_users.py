#!/usr/bin/env python3
"""coder-admin 的 JSON 用户表操作助手。

被 coder-admin 调用；也可独立测试。
用法：
  _users.py exists <db> <name>          # 输出 True/False
  _users.py nextport <db> <base>        # 输出下一个可用端口
  _users.py add <db> <name> <hash> <port>
  _users.py disable <db> <name> <ts>
  _users.py passwd <db> <name> <hash>
  _users.py list <db>
"""
import json
import sys


def load(db):
    try:
        with open(db) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {"users": []}


def save(db, data):
    with open(db, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)


def main():
    cmd = sys.argv[1]
    dbpath = sys.argv[2]

    if cmd == "exists":
        data = load(dbpath)
        print(any(u["name"] == sys.argv[3] for u in data["users"]))

    elif cmd == "nextport":
        base = int(sys.argv[3])
        data = load(dbpath)
        ports = [u["port"] for u in data["users"]]
        print(base if not ports else max(ports) + 1)

    elif cmd == "add":
        _, name, hashed, port = sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
        data = load(dbpath)
        data["users"].append({
            "name": name,
            "display_name": name,
            "password_hash": hashed,
            "port": port,
            "disabled": False,
            "archived_at": "",
        })
        save(dbpath, data)

    elif cmd == "disable":
        name, ts = sys.argv[3], sys.argv[4]
        data = load(dbpath)
        for u in data["users"]:
            if u["name"] == name:
                u["disabled"] = True
                u["archived_at"] = ts
        save(dbpath, data)

    elif cmd == "passwd":
        name, hashed = sys.argv[3], sys.argv[4]
        data = load(dbpath)
        for u in data["users"]:
            if u["name"] == name:
                u["password_hash"] = hashed
        save(dbpath, data)

    elif cmd == "list":
        data = load(dbpath)
        if not data["users"]:
            print("（暂无用户）")
            return
        print(f"{'用户名':<12} {'状态':<8} {'端口':<6} {'归档时间'}")
        print("-" * 50)
        for u in data["users"]:
            if u["disabled"]:
                st = "已禁用" if not u["archived_at"] else "待清理"
            else:
                st = "在职"
            print(f"{u['name']:<12} {st:<8} {u['port']:<6} {u['archived_at'] or '-'}")

    else:
        print(f"未知命令: {cmd}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
