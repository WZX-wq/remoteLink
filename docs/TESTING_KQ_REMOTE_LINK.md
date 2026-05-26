# KQ Remote Link 测试说明

本文档用于验证当前 Windows 测试版是否可以走通基础远程桌面流程和鲲穹 OAuth 登录流程。

## 测试包

当前可运行目录：

```text
flutter\build\windows\x64\runner\Release
```

请从这个目录启动：

```text
rustdesk.exe
```

不要只拷贝单个 `rustdesk.exe`，它需要同目录下的 `librustdesk.dll`、Flutter DLL、插件 DLL 和 `data` 目录。

测试 zip 同时包含：

- `START_KQ_REMOTE_LINK.cmd`：双击启动客户端。
- `RUN_SMOKE_CHECKS.cmd`：双击运行本机自动冒烟检查。
- `CREATE_MANUAL_TEST_REPORT.cmd`：双击生成两机验收报告模板。
- `CREATE_TWO_PC_ACCEPTANCE.cmd`：双击生成当前电脑的两机验收环境快照和角色清单。
- `COLLECT_DIAGNOSTICS.cmd`：双击收集失败诊断包。
- `README_START_HERE.txt`：给测试人员的最短入口说明。
- `Release\`：Windows 客户端运行目录。
- `TESTING_KQ_REMOTE_LINK.md`：本测试说明。
- `ACCEPTANCE_CHECKLIST.md`：真实两机验收清单。
- `SERVER_DEPLOYMENT.md`：私有服务器部署说明。
- `KQ_RELEASE_MANIFEST.json`：品牌、OAuth 参数、构建时间和可执行文件哈希。
- `deploy\`：RustDesk server compose 和自定义客户端 JSON 模板。
- `scripts\`、`tools\custom_client_signer\`：生成/验证 `custom.txt` 和检查服务器连通性的最小工具。

测试失败时，先收集诊断包：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\collect-kq-diagnostics.ps1
```

脚本会输出 `KQ-Remote-Link-diagnostics-*.zip`，包含日志、进程状态、release hash、manifest、网络摘要和经过筛选的配置摘要。

重新编译后，可以用下面的脚本生成同样结构的测试包，并顺手做一次启动冒烟检查：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package-kq-remote-link.ps1 -LaunchSmokeTest
```

如果要把已经签好的私有服务器配置一起放进测试包：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\package-kq-remote-link.ps1 -CustomTxt .\custom.txt
```

可以先运行自动验收检查，确认 release 目录、zip 包、品牌文案和 OAuth 参数没有漏：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-kq-release.ps1 `
  -PackageZip "C:\kq-remote-link-tools\KQ-Remote-Link-test-20260525-verified.zip"
```

也可以一条命令跑完可自动化的 smoke suite：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-kq-smoke-suite.ps1 `
  -PackageZip "C:\kq-remote-link-tools\KQ-Remote-Link-test-20260525-verified.zip"
```

如果测试机不能写报告目录，可以先只跑控制台检查：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-kq-smoke-suite.ps1 -NoReport
```

如果要做启动冒烟检查，请先关闭正在运行的客户端，或显式允许脚本关闭已有进程：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-kq-release.ps1 -LaunchSmokeTest -StopExistingRustDesk
```

私有服务器上线后，在客户端网络里先检查端口连通性：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-kq-server.ps1 `
  -RendezvousServer "remote.example.com:21116" `
  -RelayServer "remote.example.com:21117" `
  -ApiServer "https://remote.example.com"
```

申请服务器安全组/防火墙前，可以先生成端口申请单：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-server-port-request.ps1 `
  -ServerHost "remote.example.com" `
  -PublicIp "x.x.x.x" `
  -Requester "your-name" `
  -Environment "test"
```

鲲穹登录测试前，可以先检查授权页、Token 主机和本机回调端口：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\test-kq-oauth.ps1
```

真实两机测试前，可以生成一份可填写的验收报告：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-manual-test-report.ps1 `
  -Tester "tester-name" `
  -Controller "controller-pc" `
  -Controlled "controlled-pc"
```

也可以在两台电脑上分别生成角色化验收证据目录。被控端：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-two-pc-acceptance.ps1 `
  -Role Controlled `
  -LaunchClient
```

控制端：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-two-pc-acceptance.ps1 `
  -Role Controller `
  -PeerId "<controlled-id>" `
  -LaunchClient
```

脚本会输出 `environment.md`、`role-checklist.md` 和 `README.txt`，用于记录 release hash、IP、OAuth/私有服务器连通性和真实远控结果。

## 单机启动检查

1. 双击 `rustdesk.exe`。
2. 确认窗口标题为 `KQ Remote Link`。
3. 确认主界面能显示本机 ID、一次性密码和远程 ID 输入框。
4. 被控端建议点击界面中的安装/启用服务按钮，并按 UAC 提示授权。未安装服务时，UAC 界面、锁屏界面和部分系统级控制能力会受限。

## 鲲穹账号登录检查

1. 打开账号登录弹窗。
2. 点击 `使用鲲穹账号登录`。
3. 系统浏览器应打开鲲穹授权页：

```text
https://login.kunqiongai.com/authorize.html
```

4. 完成授权后，浏览器会回到本机回调地址：

```text
http://localhost:6613/oauth/callback
```

5. 客户端应显示已登录用户信息。

当前桌面端原型会直接在客户端用授权码换取 token。生产环境建议把 code-to-token 交换放到公司后端，避免把 `client_secret` 分发到客户端包里。

## 两端远程控制检查

准备两台电脑，或同一网络内两台虚拟机，各运行一份完整 `Release` 目录。

建议同步填写 `ACCEPTANCE_CHECKLIST.md` 或用 `new-kq-manual-test-report.ps1` 生成的报告。

1. 在被控端记录本机 ID 和一次性密码。
2. 在控制端输入被控端 ID，点击连接。
3. 选择密码连接或被控端确认连接。
4. 确认控制端可以看到被控端桌面。
5. 验证鼠标移动、点击、键盘输入。
6. 验证剪贴板双向复制。
7. 验证文件传输入口可以打开并传输小文件。
8. 分别在同局域网和跨网络环境测试一次，观察是否能通过中继保持连接。

## 私有服务器检查

当前测试包可以先使用 RustDesk 默认公共网络验证基础流程。公司生产环境建议部署私有 `hbbs` / `hbbr`：

```text
deploy\rustdesk-server.compose.yml
```

部署后，把服务器地址和 `hbbs` 公钥写入：

```text
deploy\custom-client.example.json
```

再用 `tools\custom_client_signer` 生成签名配置 `custom.txt`，并随客户端一起分发。详细步骤见：

```text
docs\SERVER_DEPLOYMENT.md
```

如果已经有 `hbbs` 地址、公钥和自定义客户端签名私钥，可以直接生成并复制 `custom.txt`：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-custom-client-config.ps1 `
  -RendezvousServer "remote.example.com:21116" `
  -RelayServer "remote.example.com:21117" `
  -ApiServer "https://remote.example.com" `
  -ServerKey "<hbbs public key>" `
  -SecretKey "<base64 secret key>" `
  -CopyToReleaseDir ".\flutter\build\windows\x64\runner\Release"
```

如果要直接生成带私有服务器 `custom.txt` 的客户端 zip，可以使用：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\new-kq-private-server-client-package.ps1 `
  -RendezvousServer "remote.example.com:21116" `
  -RelayServer "remote.example.com:21117" `
  -ApiServer "https://remote.example.com" `
  -ServerKey "<hbbs public key>" `
  -PublicKey "<custom-client public key>" `
  -SecretKey "<custom-client secret key>"
```

如果当前 release 不是用这个 `PublicKey` 构建的，加上 `-BuildClient`。
如果确认当前 release 已经用同一个 `PublicKey` 构建，才可以加
`-UseExistingBuildWithMatchingKey` 跳过重编译。

## 已知限制

- 当前机器未安装 Docker，因此本地还没有启动私有 `hbbs` / `hbbr` 做闭环验证。
- 还需要在真实两机环境中确认远控、剪贴板、文件传输、跨网络中继和真实鲲穹账号授权。
- 未安装为系统服务时，部分高权限桌面场景会受限。
