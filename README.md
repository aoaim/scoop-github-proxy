<h1 align="center">Scoop GitHub Proxy</h1>

为 Scoop 的下载流程增加 GitHub 代理链能力，方便访问 GitHub 困难地区的用户使用。

本程序本身不是代理服务，而是配合 `https://github.com/sky22333/hubproxy/` 这类 GitHub 代理程序使用。默认会使用公共代理 `https://gh-proxy.org`，你也可以再添加自己的代理地址，例如：`https://mirror.example.com`。

安装后，用户仍然使用原本的 `scoop install` 和 `scoop update <app>`。当 Scoop 下载的 URL 或 GitHub 仓库地址命中以下范围时，会自动按顺序尝试已配置的代理，全部代理失败后再回退到原始地址：

1. `github.com/*/releases/download/*`
2. `raw.githubusercontent.com/*`
3. `api.github.com/*/releases/*`
4. `https://github.com/*.git`

该程序只支持 Scoop 默认下载器，不兼容 `aria2` 下载路径。安装或执行 `repair` 时会将 Scoop 配置中的 `aria2-enabled` 设为 `false`。
该程序要求系统中可用 `git`，建议先安装 `scoop install git`。

## 设计目标

1. 作为独立 Scoop 包安装，不要求用户改用其他命令。
2. 配置持久化保存在 `persist` 目录。
3. 支持多个代理地址，按顺序重试。
4. `scoop update scoop` 覆盖补丁后，可通过 `scoop-github-proxy repair` 重新注入。

## 用户命令

```powershell
scoop-github-proxy enable
scoop-github-proxy disable
scoop-github-proxy status
scoop-github-proxy repair
scoop-github-proxy proxy list
scoop-github-proxy proxy add https://mirror1.example.com
scoop-github-proxy proxy remove https://mirror1.example.com
```

默认代理链首项是 `https://gh-proxy.org`。

安装后可以直接使用 `scoop-github-proxy ...`。

## 安装方法

当前仓库本身就是 bucket。

```powershell
scoop install git
scoop bucket add github-proxy https://github.com/aoaim/scoop-github-proxy
scoop install scoop-github-proxy
```

安装完成后，`scoop-github-proxy` 会：

1. 给 Scoop 的默认下载器注入 GitHub 代理链逻辑
2. 给 Scoop 的 GitHub `clone` / `fetch` / `pull` / `ls-remote` 流量注入代理链逻辑
3. 把 Scoop 配置中的 `aria2-enabled` 设为 `false`
4. 默认使用 `https://gh-proxy.org`
5. 当命中代理链时，在终端输出 `INFO  scoop-github-proxy: trying ...` 提示

## 使用方法

查看当前状态：

```powershell
scoop-github-proxy status
```

添加你自己的代理，优先级会排在默认代理之后：

```powershell
scoop-github-proxy proxy add https://mirror.example.com
```

查看代理列表：

```powershell
scoop-github-proxy proxy list
```

关闭代理链：

```powershell
scoop-github-proxy disable
```

重新开启代理链：

```powershell
scoop-github-proxy enable
```

如果执行过 `scoop update scoop`，导致补丁被覆盖，可以重新修复：

```powershell
scoop-github-proxy repair
```

## Scoop 本体更新后

`Scoop` 本体更新时，`$env:SCOOP\apps\scoop\current\lib\download.ps1` 可能会被新版本覆盖，因此 `scoop-github-proxy` 注入的补丁也可能丢失。
`$env:SCOOP\apps\scoop\current\lib\core.ps1` 中的 Git 代理逻辑也可能被新版本覆盖。

更新 `Scoop` 本体后，建议执行：

```powershell
scoop update scoop
scoop-github-proxy repair
```

你也可以先检查状态：

```powershell
scoop-github-proxy status
```

如果输出里显示 `repair_needed: True`，就说明需要重新执行 `repair`。

之后就正常使用 Scoop 即可，例如：

```powershell
scoop install neovim
scoop update git
scoop bucket add extras https://github.com/ScoopInstaller/Extras.git
```

## 改动范围与卸载

安装 `scoop-github-proxy` 后，该程序会修改以下内容：

1. patch Scoop 的下载脚本：`$env:SCOOP\apps\scoop\current\lib\download.ps1`
2. patch Scoop 的 Git 调用脚本：`$env:SCOOP\apps\scoop\current\lib\core.ps1`
3. 修改 Scoop 配置：将 `aria2-enabled` 设为 `false`
4. 写入自身配置：`$env:SCOOP\persist\scoop-github-proxy\config.json`

它不会修改系统代理、注册表、浏览器代理或其他包管理器配置，影响范围仅限 Scoop。

这意味着它对 Scoop 本身有一定侵入性，但不是系统级侵入。

卸载时，该程序会优先在 Scoop 本体 git 仓库中执行 `git restore lib/download.ps1 lib/core.ps1`，把 `download.ps1` 和 `core.ps1` 一起恢复到 Scoop 仓库 `HEAD` 对应的版本；如果 git 恢复失败，才退回为移除注入的补丁块。它不会自动恢复安装前的 `aria2-enabled` 原值，但会自动删除 `persist\scoop-github-proxy` 下的配置文件。

如果你自己也手动修改过 Scoop 仓库里的 `lib/download.ps1` 或 `lib/core.ps1`，`git restore` 会把这些本地修改一并丢弃。

`persist\scoop-github-proxy` 是本工具主动写入的配置目录，不依赖 manifest 的 `persist` 字段。当前版本已经没有备份目录。

推荐卸载方式：

```powershell
scoop uninstall scoop-github-proxy --purge
```

卸载后，如果你想确认是否已经恢复原样，可以直接查看 `download.ps1` 中是否已没有 `scoop-github-proxy` 的补丁标记。

如果你希望手动确认或自行恢复，最简单的方式也是直接使用 git。

`Scoop` 本体目录本身就是一个 git 仓库：

```powershell
$env:USERPROFILE\scoop\apps\scoop\current
```

如果你已经卸载了 `scoop-github-proxy`，但仍然怀疑 `download.ps1` 或 `core.ps1` 和 Scoop 仓库版本不一致，也可以在该目录下手动恢复：

```powershell
git restore lib/download.ps1 lib/core.ps1
```

这会把 `download.ps1` 和 `core.ps1` 恢复到 Scoop 仓库 `HEAD` 对应的版本。

推荐的完整卸载流程：

```powershell
scoop uninstall scoop-github-proxy --purge
cd $env:USERPROFILE\scoop\apps\scoop\current
git restore lib/download.ps1 lib/core.ps1
```

如果你需要，也可以手动恢复 `aria2`：

```powershell
scoop config aria2-enabled true
```

## 目录说明

1. `bucket/`: Scoop bucket manifest
2. `scripts/`: 安装、修复、卸载与命令入口
3. `lib/`: 配置与补丁实现

## 自动发布

可以用 GitHub Actions 自动完成发布流程。

当你 push 一个形如 `v0.0.x` 的 tag 时，工作流会自动：

1. 打包发布资产 `scoop-github-proxy-<version>.zip`
2. 计算 ZIP 的 SHA256
3. 回填 `bucket/scoop-github-proxy.json` 中的 `version`、`homepage`、`url`、`hash`、`extract_dir`
4. 提交 manifest 更新到默认分支
5. 创建 GitHub Release 并上传 ZIP

触发方式示例：

```powershell
git tag v0.0.2
git push origin v0.0.2
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
   `scoop-github-proxy enable`
   `scoop-github-proxy disable`
   `scoop-github-proxy status`
   `scoop-github-proxy repair`
   `scoop-github-proxy proxy list`
   `scoop-github-proxy proxy add <url>`
   `scoop-github-proxy proxy remove <url>`
6. 安装时自动将 Scoop 的 `aria2-enabled` 设为 `false`
7. 配置写入 `persist\scoop-github-proxy\config.json`
8. `scoop update scoop` 后可通过 `scoop-github-proxy repair` 重新注入补丁
9. GitHub Actions 自动完成 release 打包、SHA256 计算和 bucket manifest 回填

### 0.0.2

已实现：

1. 支持 GitHub 仓库地址的 `clone` / `fetch` / `pull` / `ls-remote` 代理
2. 对 `scoop update scoop`、bucket 更新、`scoop bucket add` 等 GitHub 仓库流量应用同样的代理链
3. 当流量命中代理链时，明确在终端提示正在尝试哪个 proxy URL
4. 新增 `git` 硬依赖检查，并在 manifest 中声明 `depends: git`
5. 验证多代理故障切换：错误 proxy 失败后自动切换到下一个 proxy
6. 卸载与手动恢复说明更新为同时恢复 `lib/download.ps1` 和 `lib/core.ps1`
