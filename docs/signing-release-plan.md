# Agent Light 签名与发布计划及验收记录

更新：2026-11-14。v0.1.6 本机签名、公证和 Gatekeeper 验证已完成；公开发布与 Homebrew 安装验收进行中。

## 范围

使用 Developer ID 签名和 Apple 公证，继续通过 GitHub / Homebrew 分发。
不做 Mac App Store 上架或沙盒改造。保留 bundle ID、四个可执行文件、用户设置及既有 hook。
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

## 发布顺序与剩余验收

1. [x] 签名 v0.1.6 已启动；About 版本正确，菜单/设置正常，collector 显示 2 个活跃真实会话。
2. [ ] 检查待提交文件无私钥、凭据；按仓库规定 git identity 提交并推送代码。
3. [ ] 使用新 tag v0.1.6，上传明确指定的最终 ZIP 到 draft release。
4. [ ] 手动运行 Release workflow，验证下载的 draft 包版本、Team、票据、Gatekeeper 和 SHA256。
5. [ ] 全部通过后公开 draft，下载实际公开 asset，再次验证并确认 checksum。
6. [ ] 更新 tap cask 的 version、SHA256、URL，移除旧 unsigned / xattr caveat。
7. [ ] 测试 Homebrew 升级，确认 `/Applications` 中的 v0.1.6 签名、公证、quarantine 和实际启动。
8. [ ] 提交推送 tap，验证公开安装路径及 GitHub README；记录剩余环境限制。

首个签名版本仅构建并验证 Apple Silicon（arm64），不宣称 Intel 支持。
不清空用户设置，不移除 quarantine，不关闭 Gatekeeper，不静默修改用户 hook。
新安装路径需要重新安装 hook 时，应明确说明并重启对应代理会话。
完整 clean-user 首次安装、离线首次启动、真实 Claude/Copilot 事件和登录后自启，
若无法实际验证，必须保留为未测，不能用单元测试或 spctl 结果冒充。

## 后续发布命令

```bash
swift test
python3 -m unittest discover -s Tests/ReleaseScriptsTests -v
SIGNING_IDENTITY='Developer ID Application: Ke Wang (P4P956A63K)' APPLE_TEAM_ID=P4P956A63K NOTARY_PROFILE=agent-light-release ./script/package_release.sh vX.Y.Z
```

提交推送代码和新的 tag 后，上传最终 ZIP 到 draft，手动运行 Release workflow。
CI 和本地验收通过后公开，再更新 tap。失败就停止，不上传 unsigned 替代包，不覆盖旧 tag。
已发布后发现坏包则暂停推广，修复后使用新版本，不覆盖用户下载过的 ZIP。

## 官方参考

- [Apple 公证要求](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Apple 自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [Developer ID 证书](https://developer.apple.com/help/account/certificates/create-developer-id-certificates)
