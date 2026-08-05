# SnowLuma.Docker.Framework



https://snowluma.github.io/guide/deploy/docker.html



SnowLuma 的 Linux Docker 运行框架，结构参考 `NapCat.Docker.Framework`：容器内安装 Linux QQ、Xvfb、VNC/noVNC、supervisord，并运行 SnowLuma 的 Node.js 发行产物。

## 支持平台

- [x] Linux/Amd64
- [x] Linux/Arm64

## 端口

- `5900`: VNC
- `6081`: noVNC
- `5099`: SnowLuma WebUI
- `3000`: OneBot HTTP 默认端口
- `3001`: OneBot WebSocket 默认端口

## 运行
如果你要用你当前这个仓库、本地 vendor 来构建后再跑，先构建，再起 compose：

- 先在项目创建一个 vendor 文件夹，然后 clone 一下 SnowLuma, noVNC 和 websockify
- https://github.com/SnowLuma/SnowLuma
- https://github.com/novnc/noVNC.git
- https://github.com/novnc/websockify.git

也可以：
```shell
FORCE=1 ./scripts/clone-vendors.sh
```

```shell
PLATFORM=linux/arm64 ./scripts/build-image.sh
SNOWLUMA_IMAGE=snowluma-docker-framework:latest VNC_PASSWD='你自己的VNC密码' docker compose up -d
```

如果你连 QQ 安装包也不想走外网，把它放到 vendor/qq/，文件名建议是：
vendor/qq/linuxqq_3.2.31-51102_arm64.deb
**首次启动顺序**

- 起容器。
- 浏览器打开 http://127.0.0.1:6081/，输入 VNC_PASSWD。
- 在远程桌面里扫码登录 QQ。
- 用上面那条 docker logs 命令取出 WebUI 初始密码。
- 浏览器打开 http://127.0.0.1:5099/，用 admin + 初始密码 登录。
- 在 WebUI 里确认 OneBot HTTP/WS 已启用，记下或修改 access token。



### 怎么创建一个新的机器人逻辑应用来对接

最简单的是写一个单独的 Node.js 应用，用官方 @snowluma/sdk 连 3001。官方 SDK 文档给的默认端点就是 ws://127.0.0.1:3001/ 或 http://127.0.0.1:3000/。
最小示例：

```shell
mkdir my-bot && cd my-bot
npm init -y
npm i @snowluma/sdk
```

```javascript

// index.mjs
import { SnowLumaWebSocketClient, text } from '@snowluma/sdk';

const bot = new SnowLumaWebSocketClient({
  url: 'ws://127.0.0.1:3001/',
  accessToken: process.env.SNOWLUMA_TOKEN,
  reconnect: true,
});

bot.onGroupMessage(async (event, ctx) => {
  if (event.raw_message === '/ping') {
    await ctx.reply(text('pong'));
  }
});

await bot.connect();
```


运行：

```shell
SNOWLUMA_TOKEN='你的OneBot token' node index.mjs
```

这就是一个新的“机器人逻辑应用”。SnowLuma 负责连 QQ 和暴露 OneBot；你的程序只负责业务逻辑。

**如果你不想自己写 SDK，也可以走这 3 种对接方式**

- 正向 WebSocket：你的程序主动连 ws://127.0.0.1:3001/。最适合机器人。
- HTTP API：你的程序调 http://127.0.0.1:3000/。适合脚本式调用。
- 反向 WS / HTTP 上报：在 config/onebot.json 里配 wsClients 或 httpClients，让 SnowLuma 主动连你的服务。

**你这个仓库下，最实用的一套命令**

```shell
PLATFORM=linux/arm64 ./scripts/build-image.sh
或者
PLATFORM=linux/amd64 ./scripts/build-image.sh
SNOWLUMA_IMAGE=snowluma-docker-framework:latest VNC_PASSWD='改成强密码' docker compose up -d
docker logs snowluma 2>&1 | sed -nE 's/.*(临时密码: |initial credentials: user=admin password=)([^[:space:]]+).*/\2/p' | tail -n 1
```

然后打开：

- http://127.0.0.1:6081/ 扫码登录 QQ
- http://127.0.0.1:5099/ 登录 WebUI

来源：

- 官方 Docker 部署文档：https://snowluma.github.io/guide/deploy/docker.html
- 官方配置文档：https://snowluma.github.io/guide/configuration.html
- 官方 SDK 文档：https://snowluma.github.io/sdk/
- 当前仓库 compose 文件：[docker-compose.yml](/Users/panda/github/SnowLuma.Docker.Framework/docker-compose.yml)



## 预编译产物

这个 Docker 框架默认**不在容器内重新编译 SnowLuma 源码**，直接消费 `vendor/SnowLuma`。

`vendor/SnowLuma` 需要至少包含：

- `dist/`
- `packages/runtime/package.json`
- `packages/runtime/native/`

如果你只是 `git clone` 了 SnowLuma 主仓库，通常会缺少 `dist/`，因为上游源码仓库默认不提交构建产物。此时 `scripts/build-image.sh` 会自动根据 `vendor/SnowLuma/package.json` 里的版本号，下载匹配的 SnowLuma lite runtime release，并缓存到 `artifacts/runtime/`，后续构建重复复用。

Dockerfile 会复用现成的 `dist/`，再按 `dpkg --print-architecture` 从 `packages/runtime/native/` 补齐当前架构的 Linux native 文件，所以 Apple 芯片本地构建也能直接产出 `linux/arm64` 镜像。

## 本地构建

最简：直接使用 vendored 源码构建（默认跟随宿主机架构；Apple 芯片默认 `linux/arm64`，并 `load` 到本地 Docker）：

```bash
./scripts/clone-vendors.sh
./scripts/build-image.sh
```

需要本机已装 Docker buildx。若 `vendor/SnowLuma` 缺少 `dist/`，还需要能访问 GitHub Release 下载对应 runtime。

构建并推送到镜像仓库：

```bash
IMAGE=motricseven7/snowluma:v1.6.35 PUSH=1 PLATFORM=linux/arm64 ./scripts/build-image.sh
```

切换架构：

```bash
PLATFORM=linux/arm64 ./scripts/build-image.sh
```

> Multi-arch manifest 的合并请走 CI（`.github/workflows/docker-image.yml`）— 本地脚本只支持单平台。

如果你已经把 3 个仓库 vendored 到 `vendor/`，`build-image.sh` 不再依赖任何额外 tar 包。若 `vendor/SnowLuma` 只有源码、没有 `dist/`，脚本会自动补 runtime。

## 离线 / 半离线构建

如果 GitHub / Docker Hub 访问不稳定，可以把这些依赖提前放到仓库里：

- `vendor/SnowLuma`
- `vendor/noVNC`
- `vendor/websockify`
- 可选：`vendor/qq/linuxqq_<QQ_VERSION>_<arch>.deb`

当前 Dockerfile 会直接使用 `vendor/SnowLuma`、`vendor/noVNC` 和 `vendor/websockify`，不再在线 `git clone`，也不再要求额外的 `SnowLuma.Framework.tar.gz`。如果 `vendor/SnowLuma` 里缺少 `dist/`，由 `build-image.sh` 在构建前自动补齐。

Linux QQ 安装包如果你也想本地化，按下面任一名称放到 `vendor/qq/` 即可：

- `linuxqq_<QQ_VERSION>_arm64.deb`
- `linuxqq_<QQ_VERSION>_amd64.deb`
- `linuxqq_arm64.deb`
- `linuxqq_amd64.deb`
- `linuxqq.deb`

也可以通过 `--build-arg QQ_DEB_NAME=<文件名>` 指定自定义文件名。若本地没有找到，Dockerfile 才会回退到腾讯下载地址。

## CI 自动构建

SnowLuma 主仓库每次发 tag 都会自动派发 workflow_dispatch 到本仓库的 `docker-image.yml`，参数包含 `snowluma_tag` / `snowluma_repository`。Workflow 在 `ubuntu-22.04` 和 `ubuntu-22.04-arm` 原生 runner 上分别构建 amd64 / arm64，最后用 `docker buildx imagetools` 合并 manifest 推到 Docker Hub。

也可以在 Actions 页手动触发 `docker-publish` 工作流，对任意已发布的 SnowLuma tag 重打镜像。

## 启动

```bash
./scripts/run.sh
```

或使用已发布镜像：

```bash
docker compose up -d
```

## docker run 示例

```bash
docker run -d \
  --name snowluma \
  --restart unless-stopped \
  --shm-size=1g \
  --cap-add=SYS_PTRACE \
  --security-opt seccomp=unconfined \
  -e VNC_PASSWD=vncpasswd \
  -e SNOWLUMA_WEBUI_PORT=5099 \
  -e SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing" \
  -e TZ=Asia/Shanghai \
  -p 5900:5900 \
  -p 6081:6081 \
  -p 5099:5099 \
  -p 3000:3000 \
  -p 3001:3001 \
  -v snowluma-data:/app/snowluma-data \
  -v snowluma-qq-config:/app/.config \
  -v snowluma-qq-data:/app/.local/share \
  motricseven7/snowluma:latest
```

## 常用命令

进入容器：

```bash
docker exec -it snowluma bash
```

查看日志：

```bash
docker logs -f snowluma
```

查看 supervisor 进程状态：

```bash
docker exec snowluma supervisorctl status
```

快速查找 SnowLuma WebUI 临时密码：

```bash
docker logs snowluma 2>&1 | grep -E "临时密码|initial credentials" | tail -n 1
```

只输出密码本身：

```bash
docker logs snowluma 2>&1 | sed -nE 's/.*(临时密码: |initial credentials: user=admin password=)([^[:space:]]+).*/\2/p' | tail -n 1
```

如果启动时自定义了容器名，请把命令里的 `snowluma` 替换成实际容器名。临时密码只会在全新的 `snowluma-data` 卷首次启动时输出一次；后续重启或复用旧卷时不会再生成新的明文密码。

noVNC 地址：

```text
http://IP:6081/
```

SnowLuma WebUI 地址：

```text
http://IP:5099/
```

SnowLuma 的配置和 OneBot 配置默认持久化在 `/app/snowluma-data/config`。

## 自动注入

镜像默认**开启**自动注入（`SNOWLUMA_HOOK_AUTOLOAD=1`）。容器一启动 SnowLuma 就把 hook 注入到 QQ 主进程，但只是被动观察；等你 VNC 进去扫码并在手机上完成登录后，hook 会自动识别真实登录状态并切到工作模式，rkeys / 好友 / 群信息会自动加载，无需在 WebUI 里手动点 Load。supervisor 把 QQ 自动重启后也是同样流程。

### 关闭自动注入

如果你想保留旧的"手动 Load"工作流：

```bash
docker run -e SNOWLUMA_HOOK_AUTOLOAD=0 ... motricseven7/snowluma:latest
```

或在 `docker-compose.yml` 里设 `SNOWLUMA_HOOK_AUTOLOAD: 0`，再或者在持久卷 `/app/snowluma-data/config/runtime.json` 里设 `"hookAutoLoad": false`。环境变量优先于 JSON 配置。

## 多开 QQ

镜像支持通过独立 `HOME` 自动拉起多个 QQ 实例。设置 `SNOWLUMA_EXTRA_QQ_HOMES` 为逗号或空格分隔的 `/app/...` 容器路径，并给每个路径挂独立持久卷：

```yaml
services:
  snowluma:
    environment:
      SNOWLUMA_EXTRA_QQ_HOMES: /app/qq-acct2,/app/qq-acct3
    volumes:
      - snowluma-data:/app/snowluma-data
      - snowluma-qq-config:/app/.config
      - snowluma-qq-data:/app/.local/share
      - snowluma-qq2:/app/qq-acct2
      - snowluma-qq3:/app/qq-acct3

volumes:
  snowluma-data:
  snowluma-qq-config:
  snowluma-qq-data:
  snowluma-qq2:
  snowluma-qq3:
```

容器启动时会为每个额外 `HOME` 生成一个 supervisor program，使用 `snowluma` 用户、同一个 `DISPLAY` 和同一组 `SNOWLUMA_QQ_FLAGS` 启动 QQ。这样 SnowLuma 进程和所有 QQ 进程同用户运行，hook 自动注入不会遇到手动 `docker exec` 误用 root 带来的权限问题。

临时手动启动第二个账号也可以：

```bash
docker exec -u snowluma -e DISPLAY=:1 -e HOME=/app/qq-acct2 -d snowluma sh -lc 'qq --no-sandbox ${SNOWLUMA_QQ_FLAGS}'
```

注意每个 QQ 实例必须独占自己的 `HOME`，不要让两个实例共用 `/app` 或同一个 `/app/qq-acctN`。

## GPU / 内存（SwiftShader 软件渲染泄漏）

容器内没有硬件 GPU，QQ（基于 Electron）的 GPU 进程会退回 SwiftShader 软件渲染。长时间停在登录界面（未扫码登录）时，SwiftShader 会不断分配且不回收内存，导致进程内存单调上涨。镜像默认通过 `SNOWLUMA_QQ_FLAGS` 给 QQ 关掉 GPU 与 SwiftShader：

```text
SNOWLUMA_QQ_FLAGS="--disable-gpu --disable-software-rasterizer --disable-gpu-compositing"
```

此时改走纯 CPU 光栅（Skia），登录二维码照常渲染、可正常扫码，只是不再有软件 GL 那条漏内存的路径。

如果你给容器做了 GPU 直通、想恢复硬件加速，把它清空或换成自己的参数：

```bash
docker run -e SNOWLUMA_QQ_FLAGS="" ... motricseven7/snowluma:latest
```

或在 `docker-compose.yml` 里设 `SNOWLUMA_QQ_FLAGS: ""`。

## 注意

SnowLuma 当前使用 native addon 对 QQ 进程进行加载，容器启动时需要 `SYS_PTRACE` 能力和 `seccomp=unconfined`。镜像内会给 `/usr/local/bin/node` 设置 `cap_sys_ptrace`，因此正常情况下不需要再修改宿主机 `kernel.yama.ptrace_scope`。请遵守第三方软件的使用许可和开源协议。
