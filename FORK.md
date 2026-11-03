# Fork 说明

本仓库是 [open-ani/animeko](https://github.com/open-ani/animeko) 的 fork，在上游代码之上做两件事：

1. 通过 `patches/` 里的补丁去掉播放页推荐位中的外部推广卡片；
2. 用 `.github/workflows/fork-android-release.yml` 跟随上游发布，自动打补丁、构建 Android APK 并在本仓库发布。

## 目录

| 路径 | 作用 |
| --- | --- |
| `patches/*.patch` | 相对上游代码生成的补丁，按文件名顺序应用 |
| `scripts/fork/apply-patches.sh` | 应用全部补丁（本地和 CI 共用） |
| `scripts/fork/disable-upstream-workflows.sh` | 一次性停用上游自带的 CI |
| `.github/workflows/fork-android-release.yml` | 跟随上游发布并构建 Android 包 |

## 当前补丁

`patches/0001-drop-external-promotion-recommendations.patch`

播放页的「相关推荐」接口会下发两类条目：站内番剧（带 `subjectId`）和外部推广位（带 `uri`）。
补丁在 `GetSubjectRecommendationUseCaseImpl` 里过滤掉带 `uri` 的条目，只保留站内推荐。

补丁没有合并进 `main`，而是在**构建时**应用到「上游 tag 的代码树」上，这样上游怎么改代码都不会产生合并冲突；
只有上游改到补丁涉及的同一处代码时才会失败，此时需要更新补丁。

## 一次性设置

### 1. 启用 Actions

fork 仓库默认可能需要手动确认一次 Actions 权限：仓库页面 **Actions** 标签 → 允许 workflow 运行。

### 2. 发布权限：不需要任何 secret

自动发布只用内置 `GITHUB_TOKEN`（workflow 里声明 `permissions: contents: write`），
**不需要配置 PAT**。唯一要做的设置是：**Settings → Actions → General → Workflow permissions**
选 **Read and write permissions**。没开也能跑，只是跳过 release/tag，APK 仍在运行页面的 **Artifacts** 里。

为什么不像常见做法那样用 PAT：本流水线需要把上游 tag 同步到 fork，而 GitHub 拒绝 App 令牌
把 tag 指向「带有 `.github/workflows/` 改动的上游 commit」：

```
HTTP 403: Resource not accessible by integration
x-accepted-github-permissions: contents=write; contents=write,workflows=write
```

要绕过只能用一个带 `workflow` scope 的 classic PAT —— 而 classic PAT 的 `repo` 是**账号级**权限，
能读写账号下所有仓库，为打一个 tag 把这种令牌放进 CI 不划算。实测确认（见下）：
**把 tag 打在本仓库自己的提交上则完全放行**，所以现在的做法是 tag 定位本仓库的构建提交，
上游 commit 写进 release notes 供追溯。APK 内容不受影响。

> 判断写权限不要用 `GET /repos/{owner}/{repo}` 返回的 `.permissions.push`：那是 GitHub App 的
> **安装权限**，不反映 workflow 里 `permissions: contents: write` 的实际授权，即使仓库设置已经
> 改成 Read and write，这个字段依然可能是 `false`。流水线改成真实写入探测：在默认分支 tip 上建一个临时 tag 再删掉。

实测记录（2026-11，`ci-probe` 系列临时 workflow，结论确认后已删除）：

| 操作 | 结果 |
| --- | --- |
| `git push origin refs/tags/<tag>`（tag 指向默认分支 HEAD） | ✅ 成功 |
| `POST /releases` 不带 `target_commitish` | ✅ 201 |
| `POST /releases` 带 `target_commitish=<上游 commit>` | ❌ 403（需要 `workflows=write`） |

### 3. 上游自带的 workflow

上游的 `Build` / `Release` 依赖 Apple 签名、AWS、Firebase 等只有上游才有的密钥，在 fork 里运行只会长时间失败；
`codex-agent.yml` 还要跑在 open-ani 的自建 runner 上，会永久排队；`build-ani-update.yml`、
`datasource-test-mcp.yml` 构建的是 Windows 桌面端工具，`pr-images.yml` 是给上游 PR 用的。
本 fork 只做 Android 手机端，这些一律不需要。

停用分两层，缺一不可：

1. **文件层**：7 个上游 workflow 的触发条件都改成 `workflow_dispatch`（仅手动），文件保留以便对照上游；
2. **仓库层**：`gh workflow disable` 把它们置为 `disabled_manually`，即使哪天有人点了 Enable 也不会被 push/tag 触发。

只保留 `fork-android-release.yml` 一个处于 active。如果合并上游 `main` 覆盖了文件层的改动，重跑：

```bash
bash scripts/fork/disable-upstream-workflows.sh
```

> 曾经踩过的坑：早期 tag 直接指向**上游 commit**，GitHub 会按那个 commit 里的 `release.yml` 判定触发条件，
> 于是每次推 tag 都会拉起上游 `Release`（Windows/macOS 全跳过、`Create Release` 失败），并发出失败邮件。
> 现在 tag 指向本仓库提交，读取的是本仓库「仅手动」的版本，这个问题不会再出现。

### 4. 签名密钥（已配置）

> **当前状态**：本仓库已配置稳定签名密钥（alias `animeko`，4096 位 RSA，有效期至 2056 年），
> 证书 SHA-256 指纹 `09:44:C3:FC:F2:25:D0:E3:54:65:AB:6A:FE:12:B4:70:04:B8:94:6C:ED:AF:09:AA:C4:65:58:40:EE:69:AB:40`。
> 从 `v6.4.0` 起重发布的包已用该密钥签名，后续版本可直接覆盖升级。
> 密钥库与密码**不在仓库里**，请使用 `keystore/README.txt` 记录的位置自行离线备份；
> 密钥丢失后已安装用户只能卸载重装，所以务必备份。
>
> 验证任意 APK 的签名：`apksigner verify --print-certs <apk>`，输出的 SHA-256 digest 应与上面一致。

不配置也能出包，但每次构建会生成一次性密钥，包与包之间签名不同，升级时必须先卸载。
要重新生成一套自己的 keystore：

```bash
keytool -genkeypair -keystore ani-release.jks -storetype PKCS12 \
  -alias ani -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Ani Fork, O=Ani Fork, C=CN"

# Windows 上用 base64 -w0 换成 base64 -w0 或用 PowerShell: [Convert]::ToBase64String([IO.File]::ReadAllBytes("ani-release.jks"))
base64 -w0 ani-release.jks
```

然后在仓库 **Settings → Secrets and variables → Actions** 里添加：

| Secret | 说明 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `ani-release.jks` 的 base64，单行 |
| `ANDROID_KEYSTORE_PASSWORD` | keystore 密码 |
| `ANDROID_KEY_ALIAS` | 密钥别名，如 `ani` |
| `ANDROID_KEY_PASSWORD` | 密钥密码，留空则与 keystore 密码相同 |
| `DANDANPLAY_APP_ID` / `DANDANPLAY_APP_SECRET` | 可选，弹幕服务凭据；不配置则弹幕功能不可用 |

> keystore 文件本身不要提交到仓库。

## 发布流程

- 每 6 小时（UTC `41 */6 * * *`）检查一次上游最新的正式 release；
- 发现本仓库还没有该 tag 的 release 时：
  1. 匿名读取上游 releases 接口确定 tag（跨仓库用 `GITHUB_TOKEN` 会 404）；
  2. 在同一个 job 里 fetch 上游 tag、checkout、初始化子模块，再从 `main` 取来 `patches/` 与 `scripts/fork/` 打补丁；
  3. 构建 `assembleDefaultRelease` 与 `assembleTvRelease`，APK 始终作为 artifact 上传；
  4. 用内置 `GITHUB_TOKEN` 创建 tag 与 release：tag 指向本仓库的构建提交，release notes 里记录
     实际构建所用的上游 commit 与补丁说明。

构建全程不需要额外的推送凭据，所以即使 Workflow permissions 是只读，也能拿到安装包（在运行页面的 **Artifacts** 里下载）。

### CI 维护笔记

- **ubuntu-latest 磁盘不够**：三 ABI × 两个 flavor 的 release 构建会写满默认的十几 GB，
  表现为 `Build release APKs` 这一步在执行到 9~10 分钟时被判为 `cancelled`（run 结论是 failure，日志也抓不到）。
  流水线里的 `Free disk space` 步骤会先删掉 dotnet / ghc / swift / CodeQL / NDK / 系统镜像，释放约 20 GB。
- **两个 flavor 分开构建**：手机端和 TV 端各占一步，峰值磁盘和内存减半，失败时也能直接看出是哪个 flavor。
- **tag 只能打在自家提交上**：内置 `GITHUB_TOKEN` 是 App 令牌，永远没有 `workflows` 权限，
  把 tag 指向改过 `.github/workflows/` 的上游 commit 会被 403 拒绝；指向本仓库已有提交则放行。
  所以 release 的 tag 定位构建提交，上游 commit 写在 notes 里，**不要**为了“tag 精确对应上游”
  去引入带 `workflow` scope 的 PAT（那是账号级写权限）。
- **日志兜底**：构建步骤用 `tee` 落盘，失败时把日志尾部作为 `::error::` 注释发出，
  可以通过 `check-runs` API 读到（公开仓库不需要令牌），不用登录也能排查。

也可手动触发：**Actions → Fork Android Release → Run workflow**，可指定上游 tag、强制重建、或只构建部分 ABI。

产物命名沿用上游约定：

- `ani-<版本>-universal.apk`（手机）
- `ani-tv-<版本>-universal.apk`（Android TV，包名 `me.him188.ani.tv`）

## 更新补丁

上游改到补丁涉及的代码后，CI 会在 `apply-patches.sh` 这一步失败，并指出是哪个补丁。处理方式：

```bash
# 1. 基于新版本修改代码
git fetch upstream --tags
git checkout -B fix-patch "refs/tags/<新 tag>"
# 2. 手工把补丁意图重新实现一遍
# 3. 生成新的补丁（保持只有一处改动，文件尽量小）
git diff > patches/0001-drop-external-promotion-recommendations.patch
```

然后提交到 `main` 并手动重跑该 tag 的发布（`force` 打勾）。

## 本地构建

`gradle.properties` 里写死了 `jvm.toolchain.vendor=jetbrains`，所以**必须用 JetBrains Runtime（JBR）21**，
用 Temurin / OpenJDK 会报找不到匹配的 toolchain。还需要 Android SDK 的 `platforms;android-37.0` 与 `build-tools;36.0.0`。

```bash
# 1. JBR 21（换成对应平台的文件名）
curl -L -o jbr21.tar.gz https://cache-redirector.jetbrains.com/intellij-jbr/jbrsdk-21.0.11-windows-x64-b1163.116.tar.gz
mkdir -p ~/tools/jbr && tar -xzf jbr21.tar.gz -C ~/tools/jbr --strip-components=1

# 2. Android SDK 命令行工具
curl -L -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-win-13114758_latest.zip
mkdir -p ~/tools/android-sdk/cmdline-tools && unzip cmdline-tools.zip -d ~/tools/android-sdk/cmdline-tools
mv ~/tools/android-sdk/cmdline-tools/cmdline-tools ~/tools/android-sdk/cmdline-tools/latest

# 3. 接受协议并安装需要的包
export JAVA_HOME=~/tools/jbr
yes | ~/tools/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=~/tools/android-sdk --licenses
~/tools/android-sdk/cmdline-tools/latest/bin/sdkmanager --sdk_root=~/tools/android-sdk \
  "platform-tools" "platforms;android-37.0" "build-tools;36.0.0"
```

`local.properties`（不要提交）：

```properties
jvm.toolchain.version=21
ani.android.abis=arm64-v8a
signing_release_storeFileFromRoot=keystore.jks
signing_release_storePassword=android
signing_release_keyAlias=ani
signing_release_keyPassword=android
```

`keystore.jks` 用前面生成的即可，没有就把上面四行删除。

```bash
export JAVA_HOME=~/tools/jbr
export ANDROID_HOME=~/tools/android-sdk

bash scripts/fork/apply-patches.sh          # 应用补丁
./gradlew :app:android:assembleDefaultRelease
```

产物在 `app/android/build/outputs/apk/default/release/`（`android-default-universal-release.apk`，
TV 版在 `apk/tv/release/`）。只想验证能否编译时用 `assembleDefaultDebug` 更快，也不需要签名。

首次构建要下载上 GB 依赖，国内直连 Maven Central / Google Maven 会非常慢，可以用镜像 init 脚本加速：

```groovy
// ~/gradle-cn-mirror.init.gradle
def central = 'https://maven.aliyun.com/repository/public'
def google = 'https://maven.aliyun.com/repository/google'
def plugin = 'https://maven.aliyun.com/repository/gradle-plugin'
beforeSettings { settings ->
    settings.pluginManagement.repositories {
        maven { url = uri(plugin) }
        maven { url = uri(google) }
        maven { url = uri(central) }
        gradlePluginPortal()
    }
    settings.dependencyResolutionManagement.repositories {
        maven { url = uri(central) }
        maven { url = uri(google) }
    }
}
```

```bash
./gradlew -I ~/gradle-cn-mirror.init.gradle :app:android:assembleDefaultRelease
```

Gradle 发行包本身也可以用镜像预置：把 `https://mirrors.cloud.tencent.com/gradle/gradle-9.3.1-bin.zip`
放到 `~/.gradle/wrapper/dists/gradle-9.3.1-bin/<hash>/gradle-9.3.1-bin.zip`。

## 注意

- 本 fork 的包与官方包签名不同，安装前需要先卸载官方版本；
- 上游使用 AGPLv3，分发修改版需要同时提供源码 —— 本仓库保持公开即可满足。
