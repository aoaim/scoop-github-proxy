# scoop-github-proxy

为 Scoop 的下载流程增加 GitHub 代理链能力。

它本身不是代理服务，而是配合 `https://github.com/sky22333/hubproxy/` 这类 GitHub 代理程序使用。默认会使用公共代理 `https://gh-proxy.org`，你也可以再添加自己的代理地址，例如：`https://mirror.example.com`。

安装后，用户仍然使用原本的 `scoop install` 和 `scoop update <app>`。当 Scoop 下载的 URL 命中以下范围时，会自动按顺序尝试已配置的代理，全部代理失败后再回退到原始 URL：

1. `github.com/*/releases/download/*`
2. `raw.githubusercontent.com/*`
3. `api.github.com/*/releases/*`

当前版本只支持 Scoop 默认下载器，不兼容 `aria2` 下载路径。安装或执行 `repair` 时会将 Scoop 配置中的 `aria2-enabled` 设为 `false`。

## 设计目标

1. 作为独立 Scoop 包安装，不要求用户改用其他命令。
2. 配置持久化保存在 `persist` 目录。
3. 支持多个代理地址，按顺序重试。
4. `scoop update scoop` 覆盖补丁后，可通过 `scoop github-proxy repair` 重新注入。

## 计划中的用户命令

```powershell
scoop github-proxy enable
scoop github-proxy disable
scoop github-proxy status
scoop github-proxy repair
scoop github-proxy proxy list
scoop github-proxy proxy add https://mirror1.example.com
scoop github-proxy proxy remove https://mirror1.example.com
```

默认代理链首项是 `https://gh-proxy.org`。

安装后，Scoop 会识别包里生成的 `scoop-github-proxy` shim，因此可以直接使用 `scoop github-proxy ...`。

## 目录说明

1. `bucket/`: Scoop bucket manifest
2. `scripts/`: 安装、修复、卸载与命令入口
3. `lib/`: 配置与补丁实现

## 自动发布

可以用 GitHub Actions 自动完成发布流程。

当你 push 一个形如 `v0.0.1` 的 tag 时，工作流会自动：

1. 打包发布资产 `scoop-github-proxy-0.0.1.zip`
2. 计算 ZIP 的 SHA256
3. 回填 `bucket/scoop-github-proxy.json` 中的 `version`、`homepage`、`url`、`hash`、`extract_dir`
4. 提交 manifest 更新到默认分支
5. 创建 GitHub Release 并上传 ZIP

触发方式示例：

```powershell
git tag v0.0.1
git push origin v0.0.1
```
