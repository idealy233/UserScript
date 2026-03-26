# deploy_mysql.sh

这是一个用于快速安装并初始化 MySQL 的 Bash 脚本，适合在 Ubuntu / Debian 服务器上执行。

脚本会完成这些事情：

- 安装 `mysql-server`
- 设置 MySQL 监听端口和绑定地址
- 可选设置 `root` 密码
- 创建一个业务账号并授权
- 在启用 `ufw` 时自动放行 MySQL 端口

## 使用方法

先给脚本执行权限：

```bash
chmod +x deploy_mysql.sh
```

再使用 `root` 或 `sudo` 执行：

```bash
sudo bash deploy_mysql.sh -P 3306 -u appuser -p 'App@123456' -r 'Root@123456' -b 0.0.0.0 -R true
```

## 参数说明

- `-P` MySQL 端口，默认 `3306`
- `-u` 业务用户名，必填
- `-p` 业务用户密码，必填
- `-r` root 密码，可选
- `-b` 绑定地址，默认 `0.0.0.0`
- `-R` 是否允许远程访问，`true` 或 `false`，默认 `true`
- `-h` 查看帮助

## 常见示例

仅允许本机访问：

```bash
sudo bash deploy_mysql.sh -u appuser -p 'App@123456' -b 127.0.0.1 -R false
```

允许远程访问并指定端口：

```bash
sudo bash deploy_mysql.sh -P 3307 -u appuser -p 'App@123456' -r 'Root@123456' -b 0.0.0.0 -R true
```

## 注意事项

- 需要在 Linux 服务器上运行
- 脚本依赖 `apt-get`、`systemctl`、`mysql`、`ufw`
- 用户名只支持字母、数字和下划线
- 远程开放 MySQL 前，建议确认服务器安全组和防火墙策略
