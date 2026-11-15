# Agent Light 签名与发布计划及验收记录

更新：2026-11-14。v0.1.6 已签名、公证并公开发布；本机 Homebrew 升级、重装和启动验收通过。
v0.1.7 也已签名、公证并公开发布，Homebrew 升级与安装版启动通过；
最新验收见 [v0.1.7 兼容与发布记录](v0.1.7-compatibility-checks.md)。下文保留 v0.1.6 首次签名发布记录。

## 范围

使用 Developer ID 签名和 Apple 公证，继续通过 GitHub / Homebrew 分发。
不做 Mac App Store 上架或沙盒改造。保留 bundle ID、用户设置及既有 hook。
v0.1.6 包含四个可执行文件；v0.1.7 新增 AgentCodexHook，五个文件均须签名并验证。
正常的 macOS 下载确认、通知权限和登录项审批仍可能出现。

## 凭据边界

- Developer ID Application: Ke Wang，Team ID：P4P956A63K。
- 本机 Keychain profile：`agent-light-release`；认证检查已成功。
- 证书私钥和公证凭据只保存在本机钥匙串，不导出或上传到 GitHub。
- 不向 Git、构建缓存、Release、README、聊天或日志写入私钥、口令、token。
- App 签名自带的公开证书链是正常验证材料。
- GitHub runner 使用临时 GITHUB_TOKEN 读取 draft release，不持有 Apple 凭据。

## 已完成

- [x] 本机公开 `.cer` 安装到登录钥匙串，与本机私钥配对成功。
- [x] `swift test`：176 项通过；release 构建成功。
- [x] 新增 7 个脚本测试通过，覆盖缺凭据、非法参数、签名/公证/附票失败、
  Team ID 不匹配、包内私钥材料拒绝，以及附票后重新打包的顺序。
- [x] Bash 语法、workflow YAML、git diff 空白检查通过。
- [x] 三个 helper 先签名，最后签 App，全部使用 Hardened Runtime 和时间戳。
- [x] Apple 公证返回 Accepted：`00074b66-d3e3-4c28-aa43-8afbb61a9c4e`。
- [x] staple、stapler validate、整个 bundle 签名与四个二进制 Team 校验通过。
- [x] 最终 ZIP 解压后 Gatekeeper 返回 accepted / Notarized Developer ID。
- [x] 另在临时解压包上添加 Safari quarantine 标记，保留标记验签和 Gatekeeper 检查通过。
- [x] 最终包 SHA256：`441144815d5fecabc2e6dfcfd34a965bda71952e07e0f65a02dc8d60f5dd1959`。
- [x] 上传 Apple 前及最终解压后扫描 App，未包含私钥格式或 `.p12` / `.p8` 等材料。
- [x] README、AGENTS.md 更新签名公证说明；CI 改为测试与独立验签，无需上传 Apple 密钥。

## 签名前功能基线

开发包 v0.1.5 的状态面板显示 4 个真实会话，General / Agents / Notification /
About 可打开；Claude hooks 已安装，Copilot hooks 未安装。系统显示通知允许，
但没有验证真实通知送达、完整代理事件循环或首次 onboarding。
开发包的登录项显示 macOS 找不到 App，需要在最终安装路径复测。
本机 Homebrew 管理的旧安装包为 v0.1.4，arm64，ad-hoc。

## 发布顺序与验收结果

1. [x] 签名 v0.1.6 已启动；About 版本正确，菜单/设置正常，collector 显示 2 个活跃真实会话。
2. [x] 暂存文件检查通过；发布代码及 README 已提交并推送，提交 `02643c6`。
3. [x] 新 tag v0.1.6 已推送，草稿仅上传最终 App ZIP。
4. [x] [GitHub workflow 43662911649](https://github.com/eddykwang/agent-light/actions/runs/43662911649) 测试与验签全部成功，远端 SHA256 与本地相同。
5. [x] [v0.1.6 已公开](https://github.com/eddykwang/agent-light/releases/tag/v0.1.6)，未经认证的公开下载成功，下载包验签与 checksum 再次通过。
6. [x] tap cask 的 version、SHA256、URL 已更新，旧 unsigned / xattr caveat 已移除，并声明 arm64 架构。
7. [x] `brew update` 后从 v0.1.4 升级至 v0.1.6 成功；`brew reinstall --cask agent-light` 也成功。安装版保留 quarantine，签名、公证及 Gatekeeper 检查通过；两次实际启动均直接打开状态面板，没有观察到安全拦截。
8. [x] tap 提交 `11c6b7f` 已推送；使用公开 cask 完成升级与重装，GitHub README 已核实更新。

首个签名版本仅构建并验证 Apple Silicon（arm64），不宣称 Intel 支持。
不清空用户设置，不移除 quarantine，不关闭 Gatekeeper，不静默修改用户 hook。
新安装路径需要重新安装 hook 时，应明确说明并重启对应代理会话。
完整 clean-user 首次安装、离线首次启动、真实 Claude/Copilot 事件和登录后自启，
若无法实际验证，必须保留为未测，不能用单元测试或 spctl 结果冒充。

## 实测边界与已知事项

- 已签名的 Claude/Copilot helper 以临时目录和合成事件实际执行通过：working → idle，生成 completedAt；没有改动用户 hook 配置。
- 正式安装版通知权限仍为 Allowed。真实通知送达、真实 Claude/Copilot 会话、干净用户首次 onboarding、离线首启和重登录自启未实际验证。
- 现有用户设置保留；此前登录项显示 notFound 的状态在升级后仍存在，需要用户在 Settings 中重新启用登录项；本次未改变该偏好或系统注册。
- Homebrew 升级提示 signer changed，属于从 ad-hoc 到 Developer ID 的身份变化。本机本次启动未观察到安全弹窗，但不承诺所有机器没有正常下载确认/权限提示。
- `brew update` 同时将 Homebrew 更新至 7.0.13，并执行了其常规迁移；随后升级触发默认缓存清理，未改动 Agent Light 用户数据。重装使用 NO_INSTALL_CLEANUP，未执行 zap。
- 未测试 Intel；发布包四个可执行文件均为 arm64。
- 公开 Release 仅一个 App ZIP，未包含独立证书、私钥、keychain 或凭据附件。

## 后续发布命令

```bash
swift test
python3 -m unittest discover -s Tests/ReleaseScriptsTests -v
python3 -m unittest discover -s Tests/HookHelpersTests -v
SIGNING_IDENTITY='Developer ID Application: Ke Wang (P4P956A63K)' APPLE_TEAM_ID=P4P956A63K NOTARY_PROFILE=agent-light-release ./script/package_release.sh vX.Y.Z
```

提交推送代码和新的 tag 后，上传最终 ZIP 到 draft，手动运行 Release workflow。
CI 和本地验收通过后公开，再更新 tap。失败就停止，不上传 unsigned 替代包，不覆盖旧 tag。
已发布后发现坏包则暂停推广，修复后使用新版本，不覆盖用户下载过的 ZIP。

## 官方参考

- [Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple 自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
