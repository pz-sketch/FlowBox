# ai2048.net 服务器部署说明

> 部署日期：2026-09-03 ｜ 服务器：腾讯云 `43.133.178.146`（ubuntu） ｜ 域名：`ai2048.net`（Spaceship 注册，2027-09-03 到期，自动续费已开）

## 一、总览

| 访问方式 | 指向 | 状态 |
|---|---|---|
| `https://ai2048.net` / `https://www.ai2048.net` | FlowBox 官网（Let's Encrypt 证书，自动续期） | ✅ |
| `http://ai2048.net` | 301 跳转 HTTPS | ✅ |
| 浏览器直接访问 `http://43.133.178.146` | 「蜗牛快跑」（trojan-go 伪装站，反代） | ✅ 原样保留 |
| trojan 客户端连 `43.133.178.146:443` | 透传给 trojan-go 代理 | ✅ 客户端无需改动 |
| `http://127.0.0.1:10800`（服务器本地） | opencode 代理（原有配置保留） | ✅ |

## 二、架构：443 端口 SNI 分流

服务器 80/443 由 **nginx** 统一守门，443 按 TLS SNI（域名指示）分流，三个服务共存互不干扰：

```
                          ┌─ SNI = ai2048.net / www ──→ nginx :8081（HTTPS 静态站 + LE 证书）
浏览器/客户端 ──→ :443 ──┤
                          └─ SNI = 其他/IP/留空 ─────→ trojan-go :8443（TCP 透传，代理不受影响）

                          ┌─ Host = ai2048.net ──────→ 301 → HTTPS
浏览器 ────────→ :80 ────┤
                          └─ 其他（IP 直访）─────────→ 反代 trojan-go :8080（蜗牛快跑）
```

**DNS**（Spaceship，`launch1/launch2.spaceship.net`）：

| 主机 | 类型 | 值 | TTL |
|---|---|---|---|
| `@` | A | 43.133.178.146 | 30 分钟 |
| `www` | A | 43.133.178.146 | 30 分钟 |

## 三、服务器组件

### 1. FlowBox 官网（静态站）

- 网站根目录：`/var/www/ai2048`（属主 www-data）
- 源文件：本地 `site/` 目录（与 `flowBox/` 同级）
- HTTPS 后端：nginx `:8081`（只接收 443 分流进来的流量）

### 2. trojan-go（代理 + 蜗牛快跑）

- 目录：`~/apps/trojanGo/`
- 运行方式：**systemd 服务 `trojan-go`**（开机自启、崩溃自动拉起）
- 参数：`-port 8443 -web-port 8080`（迁移前是 443/80，迁移前的启动脚本备份为 `start-linux.sh.bak`）
- 证书：自签 `CN=localhost`（不变；客户端保持"跳过证书校验"）

### 3. nginx

- 服务：`systemctl` 管理，配置入口：
  - `/etc/nginx/sites-available/ai2048` —— 80 端口两个 server + 8081 HTTPS server
  - `/etc/nginx/stream-conf.d/ai2048-split.conf` —— 443 SNI 分流（stream 模块）
  - `/etc/nginx/conf.d/opencode-proxy.conf` —— 原有的 10800 opencode 代理

### 4. 证书（Let's Encrypt，全自动续期）

- certbot webroot 模式签发，覆盖 `ai2048.net` + `www.ai2048.net`
- 证书路径：`/etc/letsencrypt/live/ai2048.net/`（有效期 90 天，当前到期日 2026-12-02）
- **自动续期链路**（已全部就位并演练通过 ✅）：
  1. `certbot.timer` 每 12 小时检查一次，到期前 30 天自动续
  2. 续期钩子 `/etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh` 在续期成功后自动 `systemctl reload nginx` 加载新证书
  3. `certbot renew --dry-run` 演练已验证成功（2026-09-03）

## 四、常用运维操作

```bash
# ── 更新网站内容（本地 site 改完后）──
cd ~/python_works/ai_swift/site
scp -r . ubuntu@43.133.178.146:/tmp/ai2048_site/
ssh ubuntu@43.133.178.146 "sudo rsync -a /tmp/ai2048_site/ /var/www/ai2048/ && rm -rf /tmp/ai2048_site"

# ── 服务管理 ──
ssh ubuntu@43.133.178.146 "sudo systemctl restart nginx"       # 重启 nginx
ssh ubuntu@43.133.178.146 "sudo systemctl restart trojan-go"   # 重启代理

# ── 查看日志 ──
ssh ubuntu@43.133.178.146 "sudo journalctl -u nginx -n 50"          # nginx
ssh ubuntu@43.133.178.146 "sudo journalctl -u trojan-go -n 50"      # 代理
ssh ubuntu@43.133.178.146 "tail -50 ~/apps/trojanGo/trojan-go.log"  # 代理应用日志

# ── 证书 ──
ssh ubuntu@43.133.178.146 "sudo certbot renew --dry-run"   # 演练续期
ssh ubuntu@43.133.178.146 "sudo certbot certificates"      # 查看有效期

# ── 改 nginx 配置后 ──
ssh ubuntu@43.133.178.146 "sudo nginx -t && sudo systemctl reload nginx"
```

## 五、注意事项

1. **trojan 客户端地址/SNI 不要填 `ai2048.net`** —— 该域名的 443 流量会被分流到官网；填 `43.133.178.146`（IP）或任何其他域名都正常走代理。
2. **不要直接改 trojan 端口/证书** —— 它现在由 systemd 管理（`/etc/systemd/system/trojan-go.service`），改参数要同步改 service 文件；动了 8443/8080 需同步改 nginx 分流配置。
3. **不要占用 80/443** —— 这两个端口归 nginx；新服务一律挂本地端口（如 8081），再到 nginx 加分流/反代。
4. **域名续费** —— Spaceship 自动续费已开启（账户余额扣款）；证书续费完全自动，无需人工干预。
5. **回滚** —— 如需恢复 trojan 直占 80/443 的原始状态：`sudo systemctl disable --now nginx trojan-go`，然后 `cd ~/apps/trojanGo && cp start-linux.sh.bak start-linux.sh && ./start-linux.sh`。
