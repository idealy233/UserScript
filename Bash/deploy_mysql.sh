#!/usr/bin/env bash
set -euo pipefail

# =========================
# 默认参数
# =========================
MYSQL_PORT="3306"
DB_USER=""
DB_PASS=""
ROOT_PASS=""
BIND_ADDRESS="0.0.0.0"   # 默认允许外部连接，可改为 127.0.0.1
ALLOW_REMOTE="true"      # true/false

usage() {
  cat <<EOF
用法:
  sudo bash deploy_mysql.sh -P <port> -u <db_user> -p <db_pass> [-r <root_pass>] [-b <bind_address>] [-R <true|false>]

参数:
  -P   MySQL 端口 (默认: 3306)
  -u   业务用户名（必填）
  -p   业务用户密码（必填）
  -r   root 密码（可选，不传则保留 socket 登录）
  -b   监听地址 (默认: 0.0.0.0)
  -R   是否允许远程访问(默认: true)
  -h   显示帮助

示例:
  sudo bash deploy_mysql.sh -P 3307 -u appuser -p 'App@123456' -r 'Root@123456' -b 0.0.0.0 -R true
EOF
}

# =========================
# 解析参数
# =========================
while getopts ":P:u:p:r:b:R:h" opt; do
  case ${opt} in
    P) MYSQL_PORT="$OPTARG" ;;
    u) DB_USER="$OPTARG" ;;
    p) DB_PASS="$OPTARG" ;;
    r) ROOT_PASS="$OPTARG" ;;
    b) BIND_ADDRESS="$OPTARG" ;;
    R) ALLOW_REMOTE="$OPTARG" ;;
    h) usage; exit 0 ;;
    \?) echo "未知参数: -$OPTARG"; usage; exit 1 ;;
    :) echo "参数 -$OPTARG 需要一个值"; usage; exit 1 ;;
  esac
done

# =========================
# 校验参数
# =========================
if [[ $EUID -ne 0 ]]; then
  echo "请使用 sudo 或 root 运行脚本"
  exit 1
fi

if [[ -z "$DB_USER" || -z "$DB_PASS" ]]; then
  echo "错误：-u 和 -p 为必填参数"
  usage
  exit 1
fi

if ! [[ "$MYSQL_PORT" =~ ^[0-9]+$ ]] || ((MYSQL_PORT < 1 || MYSQL_PORT > 65535)); then
  echo "错误：端口不合法: $MYSQL_PORT"
  exit 1
fi

if [[ "$ALLOW_REMOTE" != "true" && "$ALLOW_REMOTE" != "false" ]]; then
  echo "错误：-R 只能是 true 或 false"
  exit 1
fi

echo ">>> 开始部署 MySQL..."
echo "    端口: $MYSQL_PORT"
echo "    用户: $DB_USER"
echo "    远程访问: $ALLOW_REMOTE"
echo "    监听地址: $BIND_ADDRESS"

# =========================
# 安装 MySQL
# =========================
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

systemctl enable mysql
systemctl restart mysql

# =========================
# 修改配置文件（端口、监听地址）
# =========================
MYSQL_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"
if [[ -f "$MYSQL_CNF" ]]; then
  sed -i "s/^[#[:space:]]*port[[:space:]]*=.*/port = ${MYSQL_PORT}/" "$MYSQL_CNF" || true
  grep -qE "^[[:space:]]*port[[:space:]]*=" "$MYSQL_CNF" || echo "port = ${MYSQL_PORT}" >> "$MYSQL_CNF"

  sed -i "s/^[#[:space:]]*bind-address[[:space:]]*=.*/bind-address = ${BIND_ADDRESS}/" "$MYSQL_CNF" || true
  grep -qE "^[[:space:]]*bind-address[[:space:]]*=" "$MYSQL_CNF" || echo "bind-address = ${BIND_ADDRESS}" >> "$MYSQL_CNF"
else
  echo "未找到配置文件: $MYSQL_CNF"
  exit 1
fi

systemctl restart mysql

# =========================
# 配置 root 密码（可选）
# =========================
if [[ -n "$ROOT_PASS" ]]; then
  mysql --protocol=socket -uroot <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${ROOT_PASS}';
FLUSH PRIVILEGES;
SQL
  MYSQL_LOGIN_ROOT="mysql -uroot -p${ROOT_PASS}"
else
  MYSQL_LOGIN_ROOT="mysql --protocol=socket -uroot"
fi

# =========================
# 创建业务用户
# =========================
if [[ "$ALLOW_REMOTE" == "true" ]]; then
  USER_HOST="%"
else
  USER_HOST="localhost"
fi

# 注意：用户名不能用参数化，这里做基本校验（字母数字下划线）
if ! [[ "$DB_USER" =~ ^[a-zA-Z0-9_]+$ ]]; then
  echo "错误：用户名仅允许字母、数字、下划线"
  exit 1
fi

# 执行 SQL
$MYSQL_LOGIN_ROOT <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'${USER_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'${USER_HOST}';
FLUSH PRIVILEGES;
SQL

# 可选：禁用 root 远程
$MYSQL_LOGIN_ROOT -e "DELETE FROM mysql.user WHERE User='root' AND Host!='localhost'; FLUSH PRIVILEGES;" || true

# =========================
# 防火墙放行端口（如 ufw 已启用）
# =========================
if command -v ufw >/dev/null 2>&1; then
  if ufw status | grep -q "Status: active"; then
    ufw allow "${MYSQL_PORT}"/tcp || true
  fi
fi

echo ">>> 部署完成"
echo "MySQL 版本: $(mysql --version)"
echo "连接信息："
echo "  Host: $(hostname -I | awk '{print $1}')"
echo "  Port: ${MYSQL_PORT}"
echo "  User: ${DB_USER}"
echo "  Pass: ${DB_PASS}"