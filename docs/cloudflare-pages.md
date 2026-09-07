# Cloudflare Pages 部署 FlowBox 官网

本项目官网是 `site/` 下的纯静态站点，适合使用 Cloudflare Pages 的 Git 集成部署。

## 推荐配置：Cloudflare Git 集成

1. 将仓库推送到 GitHub。
2. 登录 Cloudflare Dashboard，进入 **Workers & Pages → Create application → Pages → Connect to Git**。
3. 选择 FlowBox 仓库和生产分支（推荐 `main`）。
4. 在构建设置中填写：
   - **Framework preset**：None
   - **Build command**：留空
   - **Build output directory**：`site`
   - **Root directory**：`flowBox`（如果 GitHub 仓库根目录本身就是 FlowBox，则留空）
5. 保存并部署。
6. 在 **Custom domains** 中绑定你的域名。Cloudflare 会提示需要添加的 DNS 记录。

每次推送到生产分支会更新正式站点；Pull Request 可以使用 Pages 预览部署检查页面后再合并。

## 发布前配置真实链接

编辑 `site/flowbox/site.config.js`：

```js
window.FLOWBOX_CONFIG = {
  productName: "FlowBox",
  version: "1.0.0",
  githubUrl: "https://github.com/你的账号/你的仓库",
  releaseUrl: "https://github.com/你的账号/你的仓库/releases/latest",
  dmgUrl: "https://github.com/你的账号/你的仓库/releases/download/v1.0.0/FlowBox.dmg",
  purchaseUrl: "https://你的支付页面",
  supportEmail: "support@example.com"
};
```

链接为空时，首页按钮会保持禁用状态，不会把占位地址展示给访客。正式发布前请确认：

- Release 文件确实存在，并注明签名、公证和 CPU 架构
- 购买页面和退款/支持政策已经上线
- GitHub 仓库 URL 与页面一致
- 隐私页和商业说明符合实际产品行为

## 使用 Wrangler（可选）

如果需要从本地或 CI 手动部署，可安装 Wrangler 并执行：

```bash
npx wrangler pages deploy site --project-name flowbox-site
```

首次执行需要登录 Cloudflare。`wrangler.toml` 已将 `site/` 声明为 Pages 输出目录；不要把 Cloudflare API Token 写入仓库。

## 回滚与预览

- 在 Pages 项目的 **Deployments** 中选择任一历史部署并回滚。
- 合并 Pull Request 前访问对应的预览 URL，检查中英文切换、按钮链接、移动端布局和隐私/商业页面。
- 发布新版本后同步更新 `site.config.js` 的版本号和下载链接。

## 第一阶段不使用 Worker

网站目前是纯静态宣传页，不接收订单、不保存购买数据，也不验证授权码。购买按钮应跳转到已选定的外部支付页面。只有在明确授权码、订单和隐私需求后，才单独增加 Cloudflare Worker、KV、D1 或其他服务。
