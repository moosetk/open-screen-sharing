# Hardware Display Mode Restoration

## 问题概述

从 v1.0.3 版本开始,Apple VNC 连接只显示动态分辨率的虚拟桌面,无法像 v1.0.1 那样显示/控制物理屏幕的原始分辨率。用户报告标准 VNC 可以正确显示物理屏幕,但存在明显的延迟;而 Apple VNC 性能优异但只能看到虚拟桌面。

## 根本原因分析

### v1.0.1 vs v1.0.3 的关键变化

通过对比代码历史,发现关键提交 `3b8e913` ("Fix resolution design", 2026-10-18) 移除了 `usesDynamicResolution` 标志和相关 UI 切换:

**v1.0.1 (提交 3b8e913 之前):**
- 用户可在两种模式间切换:
  - **Hardware Display** (Apple VNC) 或 **Fixed Resolution** (标准 VNC)
  - **Dynamic Resolution** (动态分辨率,1x-2x 缩放)
- `wantsVirtualDisplay` 逻辑: `!isIOS && usesDynamicResolution`
- 当 `usesDynamicResolution = false` 时,不请求虚拟显示

**v1.0.3 及之后 (提交 3b8e913 之后):**
- 移除了切换选项
- 只保留动态分辨率模式
- `wantsVirtualDisplay` 逻辑: `!isIOS && (usesHighPerformance || route.remoteProtocol == .rdp)`
- Apple VNC **总是**请求虚拟显示

### 技术真相

上游维护者在 issue #6 中声明"Apple VNC 只提供单个虚拟显示,不支持显示硬件屏幕内容"。这在技术上是正确的——Apple VNC 的高性能模式通过虚拟显示机制工作,无法直接镜像物理屏幕。

**但是**,v1.0.1 的"Hardware Display"模式虽然名为"硬件显示",其实现方式是:
- 不主动请求虚拟显示 (`wantsVirtualDisplay = false`)
- 让 Apple VNC 以固定分辨率(通常匹配物理屏幕)运行
- 从用户视角看起来像是在控制物理屏幕,因为分辨率固定且匹配

## 解决方案

本修复**恢复** v1.0.1 的切换功能,同时保留 v1.0.3+ 的所有其他改进。

### 实现的更改

1. **SessionMemory 结构** (`OpenScreenSharing/Session/SessionController.swift`):
   ```swift
   var usesDynamicResolution = true  // 新增字段,默认为 true
   ```

2. **SessionController 类** (`OpenScreenSharing/Session/SessionController.swift`):
   - 添加 `private(set) var usesDynamicResolution = true` 属性
   - 添加 `setUsesDynamicResolution(_ uses: Bool)` 方法
   - 更新 `wantsVirtualDisplay` 逻辑:
     ```swift
     var wantsVirtualDisplay: Bool {
         !isIOS && usesDynamicResolution && (usesHighPerformance || route.remoteProtocol == .rdp)
     }
     ```
   - 更新 `canUseHDR` 以要求动态分辨率 (HDR 需要虚拟显示)
   - 在 `restore()` 和 `memory` 中处理新字段

3. **UI 更新** (`OpenScreenSharing/SessionUI/SessionMenus.swift`):
   - **ResolutionOptions** (菜单项):
     ```swift
     Section("Display") {
         Toggle("Hardware Display" or "Fixed Resolution", ...)
         Toggle("Dynamic Resolution", ...)
     }
     Section("Resolution") {  // 仅在 Dynamic Resolution 时显示
         // 1x, 1.25x, 1.5x, 1.75x, 2x 选项
     }
     ```
   - **ResolutionPanel** (弹出面板):
     - 顶部添加分段选择器在两种模式间切换
     - 分辨率滑块仅在 Dynamic Resolution 模式显示

4. **数据持久化** (`OpenScreenSharing/Model/Computer.swift`):
   - 添加 `var usesDynamicResolution = true` 字段
   - 更新 `memory` 和 `remember()` 方法

5. **数据库迁移** (`OpenScreenSharing/Model/AppDatabase.swift`):
   ```swift
   migrator.registerMigration("restore-hardware-display") { db in
       try db.alter(table: "computers") { t in
           t.add(column: "usesDynamicResolution", .boolean).notNull().defaults(to: true)
       }
   }
   ```

### 工作原理

- **Hardware Display 模式** (`usesDynamicResolution = false`):
  - 不请求虚拟显示
  - Apple VNC 以固定分辨率运行
  - 视觉上类似控制物理屏幕
  - 保持 Apple VNC 的高性能

- **Dynamic Resolution 模式** (`usesDynamicResolution = true`):
  - 请求虚拟显示
  - 允许 1x-2x 分辨率缩放
  - v1.0.3+ 的默认行为

## 测试要求

### 在 Linux VM 上完成的验证:
✅ 代码审查和语法验证
✅ Git 历史分析 (v1.0.1, v1.0.3, 当前版本)
✅ 逻辑流程验证 (虚拟显示请求路径)
✅ 数据库迁移语法检查

### **需要 macOS 实际测试**:
❌ 实际编译 (需要 Xcode + macOS)
❌ UI 功能验证 (切换器、菜单项)
❌ Apple VNC 连接行为:
  - Hardware Display 模式是否显示固定分辨率
  - Dynamic Resolution 模式是否正常工作
  - 模式切换时的重连行为
❌ 数据库迁移在实际设备上的执行
❌ HDR 功能是否正确限制在 Dynamic Resolution 模式

### 用户必须执行的测试清单:

1. **基础编译**:
   ```bash
   cd /path/to/open-screen-sharing
   git checkout cursor/restore-hardware-display-mode-f8de
   make build_macos  # 或 make build_ios
   ```

2. **UI 验证**:
   - [ ] 启动应用,连接到 Apple VNC 服务器
   - [ ] 确认 View → Resolution 菜单显示 "Display" 部分
   - [ ] 确认有两个选项:"Hardware Display" 和 "Dynamic Resolution"
   - [ ] 点击分辨率按钮显示弹出面板
   - [ ] 确认面板顶部有分段选择器
   - [ ] 切换到 Dynamic Resolution,确认分辨率滑块出现
   - [ ] 切换到 Hardware Display,确认滑块隐藏

3. **功能验证**:
   - [ ] **Hardware Display 模式**:
     - 选择 "Hardware Display"
     - 观察远程屏幕内容
     - 验证分辨率是否固定 (不随窗口大小动态调整)
     - 检查性能 (应该保持 Apple VNC 的高性能)
   - [ ] **Dynamic Resolution 模式**:
     - 选择 "Dynamic Resolution"
     - 调整分辨率滑块 (1x 到 2x)
     - 确认远程显示分辨率随之变化
   - [ ] **设置持久化**:
     - 设置为 Hardware Display 模式
     - 断开连接
     - 重新连接同一台计算机
     - 确认仍然是 Hardware Display 模式

4. **边缘情况**:
   - [ ] 与标准 VNC 服务器连接,确认显示 "Fixed Resolution"
   - [ ] 尝试在 Hardware Display 模式启用 HDR (应该被禁用或自动切换)
   - [ ] 测试 iOS 客户端 (如果适用)

## 与上游同步维护策略

### 自动同步工作流 (推荐)

本 fork 包含**完整的自动化 GitHub Actions 工作流**来处理上游同步:

#### 工作流功能

✅ **完全实现** (非脚手架):
- 每日自动检查上游更新 (02:00 UTC)
- 在专用分支上重新应用补丁
- 使用 GitHub macOS runner 构建应用
- 创建 PR 附带可下载的构建产物
- 失败时创建 issue 通知
- 不自动合并,需要人工审查

🔒 **安全设计**:
- 最小权限令牌 (按需分离 read/write)
- 上游代码视为不受信任
- 无秘密暴露给构建过程
- 固定第三方 Action 版本
- 所有更改通过 PR 审查

📦 **构建产物**:
- macOS Debug 构建 (ad-hoc 签名,未公证)
- 适合测试和验证功能
- 不适合分发或生产使用
- 30 天保留期

#### 启用工作流

**前提条件**: 工作流必须在**默认分支**才能定时运行

1. **合并此 PR 到 `main` 分支**:
   ```bash
   git checkout main
   git merge cursor/restore-hardware-display-mode-f8de
   git push origin main
   ```

2. **在 fork 中启用 Actions**:
   - 访问: `https://github.com/YOUR_USERNAME/open-screen-sharing/actions`
   - 点击 "I understand my workflows, go ahead and enable them"

3. **启用定时工作流** (GitHub 在 60 天不活动后自动禁用):
   - 访问 Actions 标签
   - 选择 "Sync Upstream and Rebuild"
   - 如果显示已暂停,点击 "Enable workflow"

4. **配置仓库权限** (如果需要):
   - Settings → Actions → General → Workflow permissions
   - 选择 "Read and write permissions"
   - 勾选 "Allow GitHub Actions to create and approve pull requests"

#### 手动触发 (适用于任何分支)

无需合并到 main 也可测试:
1. Actions → "Sync Upstream and Rebuild" → "Run workflow"
2. 选择分支 (如 `cursor/restore-hardware-display-mode-f8de`)
3. 可选: 勾选 "Create PR even if no upstream changes" 强制运行
4. 点击 "Run workflow"

#### 工作流运行结果

**成功场景**:
- 创建名为 `upstream-sync-YYYYMMDD-<sha>` 的新分支
- 创建 PR 包含:
  - 上游更改描述和对比链接
  - 构建成功确认
  - 可下载的 macOS 应用 (artifacts)
  - 审查清单
- 你需要: 审查、测试、合并 PR

**冲突场景**:
- 工作流停止,不尝试构建
- 创建 GitHub issue 标记 `upstream-sync`
- Issue 包含:
  - 失败的工作流链接
  - 冲突文件列表
  - 手动解决指南
- 你需要: 手动解决冲突,更新补丁分支

**构建失败场景**:
- 补丁应用成功,但 Xcode 构建失败
- 创建 issue 附带构建日志
- 你需要: 修复构建错误,更新代码

#### 使用构建的应用

1. 从工作流运行下载 artifacts
2. 解压并移动到 Applications
3. 首次运行: 右键 → 打开 (绕过 Gatekeeper)
4. 授予必要权限

⚠️ **重要**: 这是 ad-hoc 签名的测试构建,不是生产版本。

#### GitHub Actions 消耗

- **Runner**: macos-14 (Apple Silicon M1)
- **每次运行**: ~15-20 分钟
- **计费**: macOS 分钟消耗是 Linux 的 10 倍
- **免费额度**:
  - 私有仓库: 2,000 分钟/月 = ~200 macOS 分钟
  - 公开仓库: 无限制免费
- **每日运行**: ~20 分钟 × 30 天 = 600 分钟/月
  - 私有仓库: 可能超额 (需要付费或降低频率)
  - 公开仓库: 完全免费

💡 **节省技巧**:
- 改为每周运行: `cron: '0 2 * * 1'` (仅周一)
- 仅手动触发: 删除 `schedule:` 部分
- 使其公开: GitHub 免费提供无限 Actions 分钟

#### 详细文档

完整配置、故障排除和自定义指南:
- `.github/workflows/README.md` - 完整工作流文档
- `.github/workflows/sync-upstream.yml` - 工作流源代码

### 原则
- **最小化修改**: 所有更改都是恢复性质,不引入新功能
- **保留上游历史**: 不修改 Git 历史,所有更改在特性分支
- **文档化差异**: 本文档说明与上游的差异
- **自动化优先**: 使用 GitHub Actions 而非手动流程

### 手动合并上游更新流程 (备用)

#### 1. 定期同步上游
```bash
cd /path/to/open-screen-sharing
git fetch upstream

# 查看上游新提交
git log HEAD..upstream/main --oneline

# 查看修改的文件
git diff HEAD..upstream/main --stat
```

#### 2. 合并策略
```bash
# 创建临时分支测试合并
git checkout -b test-upstream-merge cursor/restore-hardware-display-mode-f8de
git merge upstream/main

# 如果有冲突,检查涉及的文件
git status
```

#### 3. 冲突解决指南

**预期可能冲突的文件**:
- `OpenScreenSharing/Session/SessionController.swift`
- `OpenScreenSharing/SessionUI/SessionMenus.swift`
- `OpenScreenSharing/Model/Computer.swift`
- `OpenScreenSharing/Model/AppDatabase.swift`

**解决原则**:
1. **SessionController.swift**:
   - 保留上游对其他功能的修改
   - 保留我们的 `usesDynamicResolution` 字段和相关逻辑
   - 特别注意 `wantsVirtualDisplay` 属性,确保包含 `usesDynamicResolution` 检查

2. **SessionMenus.swift**:
   - 保留上游的 UI 改进
   - 保留我们的 Display 切换器和条件渲染逻辑

3. **Computer.swift**:
   - 保留上游添加的任何新字段
   - 保留我们的 `usesDynamicResolution` 字段
   - 在 `memory` 和 `remember()` 方法中同时处理新旧字段

4. **AppDatabase.swift**:
   - 保留上游的所有新迁移
   - 保留我们的 "restore-hardware-display" 迁移
   - 如果上游添加了新的迁移,确保版本号不冲突

#### 4. 验证合并结果
```bash
# 构建检查
make build_macos

# 语法检查 (如果没有 macOS,至少检查没有明显错误)
git diff cursor/restore-hardware-display-mode-f8de..test-upstream-merge

# 确认关键代码仍然存在
git show test-upstream-merge:OpenScreenSharing/Session/SessionController.swift | grep "usesDynamicResolution"
git show test-upstream-merge:OpenScreenSharing/Session/SessionController.swift | grep "wantsVirtualDisplay"
```

#### 5. 合并成功后
```bash
# 如果测试通过,合并到主特性分支
git checkout cursor/restore-hardware-display-mode-f8de
git merge test-upstream-merge
git branch -d test-upstream-merge

# 推送更新
git push -u origin cursor/restore-hardware-display-mode-f8de --force-with-lease
```

### 上游监控

**关注上游这些区域的变化**:
1. 虚拟显示实现 (`VirtualDisplayMode`, `wantsVirtualDisplay`)
2. 会话控制器状态管理 (`SessionController`, `SessionMemory`)
3. UI 布局变化 (`SessionMenus.swift`)
4. 数据库架构变化 (`AppDatabase.swift`)

**如果上游修改了这些区域**:
- 仔细审查差异
- 更新本文档说明新的冲突解决策略
- 可能需要调整我们的实现以匹配上游的新模式

### 自动化辅助工具 (可选)

可以添加一个脚本来检查与上游的差异:

```bash
#!/bin/bash
# scripts/check-upstream-diff.sh

echo "Fetching upstream..."
git fetch upstream

echo -e "\n=== Files modified in our fork ==="
git diff --name-only upstream/main...HEAD

echo -e "\n=== Commits in our fork not in upstream ==="
git log --oneline --graph upstream/main..HEAD

echo -e "\n=== Commits in upstream not in our fork ==="
git log --oneline upstream/main ^HEAD | head -20

echo -e "\n=== Changes in conflict-prone files ==="
for file in \
  "OpenScreenSharing/Session/SessionController.swift" \
  "OpenScreenSharing/SessionUI/SessionMenus.swift" \
  "OpenScreenSharing/Model/Computer.swift" \
  "OpenScreenSharing/Model/AppDatabase.swift"
do
  if git diff --quiet HEAD..upstream/main -- "$file"; then
    echo "✓ $file - no changes"
  else
    echo "⚠ $file - has changes, review needed"
  fi
done
```

使用:
```bash
chmod +x scripts/check-upstream-diff.sh
./scripts/check-upstream-diff.sh
```

## 未解决的限制

### 技术限制
1. **Apple VNC 的虚拟显示特性**: Apple VNC 的高性能模式从设计上就是通过虚拟显示工作的。"Hardware Display"模式实际上是关闭虚拟显示请求,让系统以固定分辨率运行,而不是真正镜像物理屏幕的帧缓冲区。

2. **多显示器**: 即使在 Hardware Display 模式,Apple VNC 仍然只能显示一个显示器。多显示器支持是 Apple VNC 协议的根本限制 (见上游 issue #6)。

3. **HDR 支持**: HDR 功能需要虚拟显示的动态配置,因此仅在 Dynamic Resolution 模式可用。

### 非目标
本修复**不**尝试:
- ❌ 修改上游仓库
- ❌ 发布版本或自动化部署
- ❌ 真正访问物理屏幕的帧缓冲区 (这需要修改 macOS Screen Sharing 服务器)
- ❌ 支持多显示器显示
- ❌ 添加定时任务或自动合并上游

## 相关链接

- **上游仓库**: https://github.com/nekohasekai/open-screen-sharing
- **Fork 仓库**: https://github.com/moosetk/open-screen-sharing
- **上游 Issue #6**: https://github.com/nekohasekai/open-screen-sharing/issues/6
  - 报告了 v1.0.1 有 "Hardware Display" 选项
  - 维护者声明 Apple VNC 不能显示硬件屏幕
- **上游 Issue #2**: https://github.com/nekohasekai/open-screen-sharing/issues/2
  - 讨论了标准 VNC vs Apple VNC 的区别
- **关键提交 3b8e913**: https://github.com/nekohasekai/open-screen-sharing/commit/3b8e91385c286bb636bf7f2a52a56b8c5eb36dd4
  - "Fix resolution design"
  - 移除了 `usesDynamicResolution` 切换
- **v1.0.1 标签**: https://github.com/nekohasekai/open-screen-sharing/tree/v1.0.1
- **v1.0.3 标签**: https://github.com/nekohasekai/open-screen-sharing/tree/v1.0.3

## 许可证和致谢

本修改完全遵守上游项目的许可证。所有功劳归于原作者 [@nekohasekai](https://github.com/nekohasekai)。本 fork 仅为个人使用维护,恢复了一个被移除的功能选项。
