# Rhythm 发布流程

Rhythm 采用三层发布链：普通 CI、Release Candidate、Production Release。
正式产物只由 GitHub Actions 生成，不从开发机手工上传。

## 流程形状

- `.github/workflows/ci.yml`
  - `main` push 和 pull request 在 `macos-26` 上运行发布脚本自检、格式检查、构建、单元测试。
- `.github/workflows/release-candidate.yml`
  - 仅手动触发。
  - 使用 `release-candidate` environment。
  - 构建、签名、公证并上传保留 14 天的候选 artifact。
  - 不创建 GitHub Release。
- `.github/workflows/release.yml`
  - 推送 `v*` tag 时正式运行，也可手动创建安全的 draft/prerelease。
  - 使用 `production` environment 构建签名产物。
  - build job 只有 `contents: read`；独立 publish job 才有 `contents: write`。
  - 先创建 draft、上传并验证全部资产，最后才公开 Release。

workflow 使用的 GitHub Actions 固定到完整 commit SHA；签名 job 不加载第三方 setup action。

当前流程不包含 Sparkle 或自动更新。发布产物是签名并公证的 arm64 DMG。

## GitHub Environments

创建两个 environment：

- `release-candidate`
- `production`

给 `production` 配置 required reviewer；environment deployment rules 只允许 `main` 和受保护的 `v*` tag。
`release-candidate` 只允许 `main`。这样手动 workflow 不能从其他分支取得发布凭据。

两个 environment 都需要以下 secrets：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APP_SPECIFIC_PASSWORD`
- `DEVELOPER_ID_APPLICATION_P12_BASE64`
- `DEVELOPER_ID_APPLICATION_P12_PASSWORD`

这些凭据只放在 environment，不要再配置同名 repository secrets。

兼容旧名称 `NOTARY_APPLE_ID` 和 `NOTARY_APP_PASSWORD`，但新配置统一使用上面的名称。
临时 keychain 密码由 runner 生成，不需要 `KEYCHAIN_PASSWORD` secret。

可选 variables：

- `DEVELOPER_ID_APPLICATION`
  - 完整签名 identity；未设置时使用 `Developer ID Application`。
- `ARCHIVE_PROVISIONING_PROFILE_SPECIFIER`
  - 只有签名 entitlement 需要 distribution provisioning profile 时才配置。

## 版本规则

发布标签只接受：

- 正式版：`vMAJOR.MINOR.PATCH`
- 候选版：`vMAJOR.MINOR.PATCH-rcN`

项目版本必须满足：

```text
MARKETING_VERSION = MAJOR.MINOR.PATCH
CURRENT_PROJECT_VERSION = MAJOR * 1,000,000 + MINOR * 1,000 + PATCH
```

例如 `1.2.3` 的 build number 是 `1002003`。`MINOR` 和 `PATCH` 必须小于或等于 999。

只修改版本、不 commit/tag/push：

```bash
./Scripts/bump-version.sh 1.2.3
```

提交前可检查版本元数据：

```bash
GITHUB_REPOSITORY=DengNaichen/Rhythm \
GITHUB_TAG=v1.2.3-rc1 \
RELEASE_COMMIT_SHA="$(git rev-parse HEAD)" \
./Scripts/release.sh preflight
```

## Release Candidate

1. 运行 `bump-version.sh`。
2. 提交改动并合并、推送到 `main`。
3. 在 Actions 手动运行 `macOS Release Candidate`。
4. `release_tag` 使用类似 `v1.2.3-rc1` 的标签。
5. 下载 artifact，验证安装、启动、Calendar 权限、Things 自动化和 MCP 连接。

workflow 只签名当前 `origin/main` 的精确 commit；历史 commit 和 feature branch 都不能接触发布 secrets。

## 正式发布

RC 验证通过后：

```bash
git tag -a v1.2.3 -m "Release v1.2.3"
git push origin v1.2.3
```

`macOS Release` 会：

1. 确认 tag commit 等于当前 `origin/main`。
2. 再次运行格式检查、无签名构建和单元测试。
3. 使用 Developer ID 创建 arm64 Release archive。
4. 单独签名 `rhythm-server`，再签名并严格验证主 app。
5. 创建带 `/Applications` 快捷方式的 DMG。
6. 签名、公证、staple 并验证 DMG。
7. 生成 checksum 和 release manifest。
8. 上传 Actions artifact。
9. 创建 draft GitHub Release，上传并验证资产。
10. 最后公开 release；稳定版标记为 Latest，`-rcN` 标记为 prerelease。

手动运行 `macOS Release` 只接受 `-rcN` 标签，并始终保留为 draft/prerelease，用于验证完整发布链。
preflight 与签名 job 会核对 Xcode build version，工具链漂移会直接失败。

## 产物契约

每次成功构建包含：

- `Rhythm-vX.Y.Z-macos-arm64.dmg`
- 同名 `.sha256`
- `release-manifest.json`
- `notary-submission.plist`
- `notary-log.json`（Apple 返回时）

manifest 记录 tag、版本、build、commit SHA、架构、最低 macOS 版本、Xcode 版本、DMG SHA-256 和 notarization submission ID。

## 本地诊断

复制 `.env.release.example` 为 `.env.release` 并填写本地值；该文件已被 Git 忽略。

```bash
./Scripts/setup-notarytool-profile.sh
./Scripts/release.sh preflight
./Scripts/release.sh build
```

本地 build 仍需要 Developer ID identity、Apple notarization credentials，并要求工作树完全干净。

## 当前发布边界

- 产物固定为 arm64；主 app 和 `rhythm-server` 架构不一致时脚本会失败。
- 当前最低系统版本来自项目设置（现为 macOS 26.2）。
- 当前没有 Sparkle、自更新、Homebrew cask、PKG、SBOM 或 provenance attestation。
