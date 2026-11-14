# OpenFOAM + phynexis-foam：CI 与发布流程设计（2026-11-11 审查后起草）

依据：天河星逸 v1→v13 裸机构建实战排障记录 + 既有打包管线（`make dist-native`）。
目标：构建一次、多处安装（工作站 / sysu-linux / 天河 / 用户机），版本可回溯。

## 1. 构建机制现状（先对齐事实）

- OpenFOAM 本体走**它自己的原生构建系统**：`Allwmake -j N`（顶层驱动）+
  wmake（每模块 `Make/files` 描述）。本仓不替它写 makefile。
- 本仓 `makefile` 只是外层驱动：`all: openfoam cli`；
  `scripts/build_openfoam.sh` 负责 sync 源码 → 写 `etc/prefs.sh`（Linux 路径）→
  调 `./Allwmake -j "${NUM_JOBS}" -s [-q -k]`。
- 发布打包：`make dist-native` → `scripts/stage_openfoam.sh` /
  `openfoam_pack.sh` / `bundle_fix_rpath.sh` / `verify_openfoam_pack.sh`，
  产出 `dist-native/phynexis-foam-2412-linux-amd64.tar.gz` + whl。
  产物已用 `$ORIGIN` 相对 RUNPATH，库布局问题已解决。

## 2. 发布基线政策（本次最重要的教训）

### 2.0 构建入口策略（2026-11-12 补）

**规范入口是仓里的 `makefile`，不是 `scripts/build_openfoam.sh`。**

- 正常路径（容器内 / 开发机）：一律 `make openfoam` / `make dist-native`。
  make 层的前置 target 有真实价值：`sync-submodule`（钉住 openfoam-source
  的 submodule 版本，可复现性的来源）、`check-deps`、`get-jobs`，
  以及打包 target 的完整链。`install.sh` 只是薄封装，`build_openfoam.sh`
  直调**不算**规范路径。
- 逃生门（无 docker、无 apt 的超算等 exotic 环境）：才允许直调
  `build_openfoam.sh`（配合 §5 的 toolroot），但必须手工补做
  `sync-submodule` 的等价动作——记录 openfoam-source 的 commit/tag
  进 manifest。2026-11-11 天河 v1–v13 直调没有钉版，是已知缺口。
- CI 门禁：verify 阶段校验 manifest 里必须同时有 foam-repo commit 和
  openfoam-source 的 submodule commit，缺一即拒。

### 2.0.1 容器后端（插件）

容器命令不绑定 Docker。`docker/*.sh` 一律调用 `cb`（`docker/container-backend.sh`），
实际 CLI 由 `CONTAINER_BACKEND` 选择：

| 值 | CLI | 说明 |
|----|-----|------|
| `auto`（默认） | docker → podman → apple | 取第一个可用 |
| `docker` | Docker Engine / Desktop | `buildx` 负责 `--platform` |
| `podman` | Podman | 原生 `podman build`；`imagetools inspect` 需 skopeo |
| `apple` | Apple `container`（macOS 26+） | `--arch` 替代 `--platform`，arm64 上跑 amd64 加 `--rosetta` |

新增后端只需写 `_cb_<name>` 并登记到 `_cb_detect`；其余脚本不变。
`make` 侧：`CONTAINER_BACKEND=apple make docker-dist-native ...`。

**glibc 只能向后兼容：构建机 glibc ≤ 运行机 glibc。**

- 发布基线 = **Ubuntu 22.04 / glibc 2.35**（当前 LTS 主流，覆盖天河与用户机）；
- 构建环境 = `docker/Dockerfile.build`（`ARG UBUNTU_VERSION` 已参数化，
  发布构建固定 `22.04`），镜像 digest 记入 manifest；
- 24.04 宿主（ts-linux-ws、sysu-linux）**原生构建的产物不得发布**——只能
  在 22.04 容器里编（宿主版本无所谓）；
- 产物验收硬门槛：ELF 符号表扫描，`GLIBC_2.xx` 最高版本 ≤ 2.35
  （`objdump -T` 全库扫描，写进 verify 脚本）。

## 3. v1→v13 失败分类 → 流水线必须内置的对策

| 失败 | 根因 | CI/发布对策 |
|---|---|---|
| module/执行位/路径假设 | 裸机环境差异 | 容器内构建即全部消除；toolroot 仅作无 docker 退路 |
| GLIBC_2.38 符号（libtalloc、产物） | 在 24.04 上编、22.04 上跑 | §2 基线政策 + 符号扫描门禁 |
| proot/chroot 限制（/dev 空、挂载禁、EACCES） | 超算内核限制 | 不依赖：容器优先，toolroot 直跑兜底 |
| relocated gcc 丢头文件/库路径 | gcc 认编译期前缀 | toolroot env 三件套：`C_INCLUDE_PATH`/`CPLUS_INCLUDE_PATH`/`LIBRARY_PATH`（multiarch 子目录必须给全） |
| `ln -s` 并发竞态（Lustre 元数据延迟） | wmakeLnInclude 非原子 | 源码补丁 `ln -s → ln -sf`（同步阶段自动应用；争取上游） |
| rsync 等工具缺失 | 极简计算节点 | toolroot 打包时显式含 rsync；preflight 检查清单 |
| 队列/分区差异 | deimos 满、phobos 空 | 与集群无关，但 CI 提交层要支持分区回退 |

## 4. 建议的 CI 工作流（Gitea Actions，runner 在 ts-linux-ws）

**已按 xiaohe-agent 惯例落地（2026-11-12）**：`.github/workflows/` 一设备一文件，
与 `agent-linux / client-darwin` 同帧同纪律：

| 文件 | 设备 | 构建 | runner（vars） |
|------|------|------|----------------|
| `foam-dist-linux-amd64.yml` | Linux 发布基线 | ubuntu:22.04 容器内 `make dist-native` | `FOAM_CI_RUNNER_LINUX`（ts-linux-ws，capacity=1） |
| `foam-dist-darwin-arm64.yml` | macOS arm64 | 原生 `make dist-native` | `FOAM_CI_RUNNER_DARWIN`（ts-mac） |

对齐要点（全部继承 xiaohe-agent 模式）：workflow_dispatch 手动触发（默认不
push 自动跑）、`upload_only` 调试输入、build → verify → upload-beta →
install-beta 四 job 同帧、drop 经同 runner 的 `~/.xiaohe/ci-drop/<device>/`
交接（不用 GitHub artifacts）、`CI_GIT_TOKEN` 收 submodule、`XIAOHE_VPS_*`
secrets 共用 dufs beta 通道、promote 公开渠道永远手动。verify 内含 manifest
生成、glibc 地板扫描（linux）/ install_name 检查（darwin）、`ldd -r` 与
bashrc 冒烟。待 ops 补 `scripts/publish.sh --beta` 与
`ci/install-from-beta.sh` 后打开 upload/install 两个 job 的实际发布逻辑。

### 4.1 与既有 CI（ci.yml / native-build.yml / release.yml）的对齐审查

既有三文件是**GitHub 托管 runner 的 PR 检查/发布**框架（reusable
`native-build.yml` + runner 矩阵）。审查发现两处与基线政策冲突，per-device
文件就是修正：

1. **`ubuntu-latest` 漂移风险**：现有 release 矩阵用 GH 托管 runner，
   `ubuntu-latest` 当前 = 24.04 → 编出的发布包带 GLIBC_2.38+ 符号，
   正是 2026-11 天河 v1–v14 撞上的那堵墙。**发布构建必须固定在
   ubuntu:22.04 容器（本仓 Dockerfile.build）**，GH 托管 runner 只适合做
   PR 级检查。
2. **`BUILD_JOBS: 2`**：全量 OpenFOAM 编译在 GH runner 上 180 分钟超时
   边界很紧；per-device 文件里 Linux 走自托管 runner + 容器（16 jobs），
   darwin 走自托管 ts-mac。

分工约定：per-device 两个文件是**发布唯一通道**；`ci.yml`（PR 检查）继续
用 `native-build.yml` 不冲突；`release.yml` 待改写成调用 per-device 文件
（TODO），不再自带 runner 矩阵。`native-build.yml` 里 macOS 大小写敏感
sparseimage 的处理已并入 `foam-dist-darwin-arm64.yml`。

历史方案（供参考的工作流骨架）：

```
push main( nightly ) / tag v* ( release )
  └─ job build-image   : docker build Dockerfile.build (UBUNTU_VERSION=22.04)
                         → 镜像 tag + digest 入 manifest
  └─ job dist-native   : 容器内 make dist-native
                         → tar + whl + build-manifest.json
  └─ job verify        : verify_openfoam_pack.sh
                         + glibc 符号扫描 ≤ 2.35
                         + 冒烟：干净目录 source bashrc，toy case 跑 blockMesh，
                           ldd -r 无 not found
  └─ job publish       : Gitea release / package registry（附 manifest）
```

`build-manifest.json` 规范：

```json
{
  "version": "dev-20261111-g6bacaad",
  "commit_foam_repo": "6bacaad0…",
  "commit_openfoam_source": "v2412 + patches:<hash>",
  "ubuntu_baseline": "22.04", "glibc_floor": "2.35",
  "image": "foam-build-env@sha256:…",
  "built_at": "…", "builder": "ts-linux-ws",
  "artifacts": {"phynexis-foam-2412-linux-amd64.tar.gz": "sha256:…"}
}
```

## 5. 无 docker 环境（超算）退路：toolroot 产品化

把今天手工趟出的 toolroot 固化成 `scripts/make_toolroot.sh`：

1. 从 `foam-build-env` 镜像（或 jammy deb 集）抽取
   `/usr/bin + /usr/lib + /usr/include + /usr/libexec` 到单个目录；
2. 生成 `toolroot/env.sh`：PATH / LD_LIBRARY_PATH / C_INCLUDE_PATH /
   CPLUS_INCLUDE_PATH / LIBRARY_PATH 三件套（含 multiarch 子目录）；
3. 同步阶段自动应用 wmakeLnInclude `ln -sf` 补丁；
4. preflight：检查 rsync、make、磁盘余量，缺什么给什么。

CI 里加一条 **conformance（一致性）测试**：固定一个基准算例（ten Cate case-1，
d/dx=12，200 步），装包机器跑完与参考轨迹比对（终速差 ≤ 1%、轨迹 L2 ≤ 阈值），
作为每台跑机的验收门槛。

## 6. 待办清单

- [ ] `ln -sf` 补丁进 sync 流程（或上游 OpenCFD）
- [ ] `scripts/make_toolroot.sh`（§5），内置源码钉校（逃生门补 sync-submodule）
- [ ] glibc 符号扫描并入 `verify_openfoam_pack.sh`
- [ ] manifest 生成并入打包管线；Gitea workflow 用 `make dist-native` 作唯一入口
- [ ] `release.yml` 改写为调用 per-device 工作流（去掉自带 runner 矩阵）
- [ ] Gitea 仓 vars：`FOAM_CI_RUNNER_LINUX`（ts-linux-ws, capacity=1）、`FOAM_CI_RUNNER_DARWIN`（ts-mac）；secrets 复用 `XIAOHE_VPS_*` + `CI_GIT_TOKEN`
- [ ] conformance 基准算例与阈值标定
- [ ] make-config-user.mk 增加 Linux/HPC 预设（消除 Mac 默认值在异机的误导）
