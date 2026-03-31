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

## 安装方法

```powershell
scoop bucket add github-proxy https://github.com/aoaim/scoop-github-proxy
scoop install scoop-github-proxy
```

安装完成后，`scoop-github-proxy` 会：

1. 给 Scoop 的默认下载器注入 GitHub 代理链逻辑
2. 把 Scoop 配置中的 `aria2-enabled` 设为 `false`
3. 默认使用 `https://gh-proxy.org`

## 使用方法

查看当前状态：

```powershell
scoop github-proxy status
```

添加你自己的代理，优先级会排在默认代理之后：

```powershell
scoop github-proxy proxy add https://mirror.example.com
```

查看代理列表：

```powershell
scoop github-proxy proxy list
```

关闭代理链：

```powershell
scoop github-proxy disable
```

重新开启代理链：

```powershell
scoop github-proxy enable
```

如果执行过 `scoop update scoop`，导致补丁被覆盖，可以重新修复：

```powershell
scoop github-proxy repair
```

## Scoop 本体更新后

`Scoop` 本体更新时，`$env:SCOOP\apps\scoop\current\lib\download.ps1` 可能会被新版本覆盖，因此 `scoop-github-proxy` 注入的补丁也可能丢失。

更新 `Scoop` 本体后，建议执行：

```powershell
scoop update scoop
scoop github-proxy repair
```

你也可以先检查状态：

```powershell
scoop github-proxy status
```

如果输出里显示 `repair_needed: True`，就说明需要重新执行 `repair`。

之后就正常使用 Scoop 即可，例如：

```powershell
scoop install neovim
scoop update git
```

## 改动范围与卸载

安装 `scoop-github-proxy` 后，当前版本会修改以下内容：

1. patch Scoop 的下载脚本：`$env:SCOOP\apps\scoop\current\lib\download.ps1`
2. 修改 Scoop 配置：将 `aria2-enabled` 设为 `false`
3. 写入自身配置：`$env:SCOOP\persist\scoop-github-proxy\config.json`

它不会修改系统代理、注册表、浏览器代理或其他包管理器配置，影响范围仅限 Scoop。

这意味着它对 Scoop 本身有一定侵入性，但不是系统级侵入。

卸载时，当前版本会移除注入到 Scoop 下载脚本中的补丁块；但不会自动恢复安装前的 `aria2-enabled` 原值，也不会自动删除 `persist\scoop-github-proxy` 下的配置文件。

`persist\scoop-github-proxy` 是本工具主动写入的配置目录，不依赖 manifest 的 `persist` 字段。

如果你需要完全恢复到安装前状态，目前还需要手动：

1. 根据你的需要重新设置 `scoop config aria2-enabled true`
2. 删除 `persist\scoop-github-proxy` 目录

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

## Changelog

### 0.0.1

已实现：

1. 作为 Scoop 包安装后，继续使用原生 `scoop install` 和 `scoop update <app>`
2. 拦截以下 GitHub URL：
   `github.com/*/releases/download/*`
   `raw.githubusercontent.com/*`
   `api.github.com/*/releases/*`
3. 默认使用 `https://gh-proxy.org`
4. 支持多个代理按顺序尝试，最后回退原始 URL
5. 支持命令：
   `scoop github-proxy enable`
   `scoop github-proxy disable`
   `scoop github-proxy status`
   `scoop github-proxy repair`
   `scoop github-proxy proxy list`
   `scoop github-proxy proxy add <url>`
   `scoop github-proxy proxy remove <url>`
6. 安装时自动将 Scoop 的 `aria2-enabled` 设为 `false`
7. 配置写入 `persist\scoop-github-proxy\config.json`
8. `scoop update scoop` 后可通过 `scoop github-proxy repair` 重新注入补丁
9. GitHub Actions 自动完成 release 打包、SHA256 计算和 bucket manifest 回填

修复：

1. 修复安装时对 `SCOOP` 环境变量的强依赖
2. 修复补丁模板变量插值错误
3. 移除错误的 manifest `persist` 配置

### 0.0.2

计划新增：

1. 在修改 Scoop 的 `download.ps1` 之前，先自动备份原始脚本
