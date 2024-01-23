#!/bin/bash

PASSWORD=""
PORT=""
COMMENT=""

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查当前用户的 UID 是否为 0（root 用户）
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}请使用 root 用户运行脚本${NC}"
    exit 1
fi

while [[ $# -gt 0 ]]; do
    case $1 in
    -pwd | -password)
        PASSWORD="$2"
        shift
        shift
        ;;
    -p | -port)
        PORT="$2"
        shift
        shift
        ;;
    -c | -comment)
        COMMENT="$2"
        shift
        shift
        ;;
    *)
        echo -e "${RED}无效参数: $1${NC}" >&2
        exit 1
        ;;
    esac
done

# 生成 SSH 密钥
if [ ! -f ~/.ssh/id_rsa ]; then
    echo -e "${YELLOW}正在生成 SSH 密钥...${NC}"
    ssh-keygen -q -t ed25519 -f ~/.ssh/id_rsa -N "$PASSWORD" -C "$COMMENT" && \
    mv ~/.ssh/id_rsa.pub ~/.ssh/authorized_keys && \
    chmod 700 ~/.ssh && \
    chmod 600 ~/.ssh/authorized_keys
else
    echo -e "${YELLOW}检测到已存在私钥，跳过生成 SSH 密钥${NC}"
fi

# 生成一个随机端口
if [ -z "$PORT" ]; then
    excluded_ports=(21 22 25 80 443 143 110 3306 5432 6379 8080 27017)
    PORT=$(shuf -i 0-65535 -n 1)
    while ss -tln | grep ":$PORT" > /dev/null || [[ " ${excluded_ports[@]} " =~ " $PORT " ]]; do
        PORT=$(shuf -i 0-65535 -n 1)
    done
fi

# 备份 SSH 配置文件
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# 更改 SSH 配置文件
echo -e "${YELLOW}正在修改 SSH 配置文件...${NC}"
sed -i 's/^\s*#\?\(\s*PasswordAuthentication\s*\)\(yes\|no\)\s*$/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^\s*#\?\(\s*ChallengeResponseAuthentication\s*\)\(yes\|no\)\s*$/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config
sed -i 's/^\s*#\?\(\s*PubkeyAuthentication\s*\)\(yes\|no\)\s*$/PubkeyAuthentication yes/' /etc/ssh/sshd_config
sed -i "s/^\s*#\?\(\s*Port\s*\)[0-9]*\s*$/Port $PORT/" /etc/ssh/sshd_config

# 重启 SSH
echo -e "${YELLOW}正在重启 SSH 服务...${NC}"
systemctl restart sshd

# 检测 SSH 是否正常运行
if systemctl is-active --quiet sshd; then
    echo -e "${GREEN}SSH 服务已成功重启，新端口为 $PORT，请注意修改防火墙设置${NC}"
    echo -e "${GREEN}已禁用密码登录，启用密钥登录${NC}"
    echo -e "${GREEN}请及时保存生成的私钥${NC}"
else
    echo -e "${RED}SSH 服务启动失败，正在恢复原始配置并重启 SSH 服务${NC}"
    mv /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    # rm ~/.ssh/authorized_keys ~/.ssh/id_rsa
    systemctl restart sshd
    echo -e "${YELLOW}SSH 服务已恢复原始配置。${NC}"
    exit 1
fi
