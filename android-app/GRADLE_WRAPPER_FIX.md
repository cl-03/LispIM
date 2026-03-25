# Gradle Wrapper 修复指南

## 问题说明

由于网络限制，`gradle-wrapper.jar` 文件无法自动下载。需要手动获取此文件才能构建项目。

**当前状态**: `gradle/wrapper/gradle-wrapper.jar` 缺失

---

## 解决方案（按优先级排序）

### 方案 1：使用 Android Studio（强烈推荐）

这是最简单且最可靠的方法，Android Studio 会自动处理所有 Gradle 配置。

**步骤**：
1. 打开 Android Studio
2. **File → Open** → 选择 `D:\Claude\LispIM\android-app`
3. Android Studio 会自动下载 Gradle 并完成配置
4. 等待底部状态栏显示 "Gradle sync finished"
5. 点击 Run 按钮运行应用

**优点**：
- 全自动，无需手动配置
- 自动解决依赖问题
- 提供完整的开发环境

---

### 方案 2：手动复制 gradle-wrapper.jar

如果你有其他 Android 项目或 Android Studio 安装：

#### 从 Android Studio 复制
```bash
# 查找 Android Studio 的 gradle 安装
# 通常在以下位置之一：
C:\Program Files\Android\Android Studio\plugins\gradle\lib\gradle-wrapper.jar
C:\Program Files (x86)\Android\Android Studio\plugins\gradle\lib\gradle-wrapper.jar

# 复制到项目
copy "C:\Program Files\Android\Android Studio\plugins\gradle\lib\gradle-wrapper.jar" ^
     "D:\Claude\LispIM\android-app\gradle\wrapper\gradle-wrapper.jar"
```

#### 从其他 Android 项目复制
```bash
# 如果你有其他 Android 项目
copy "C:\path\to\other\android\project\gradle\wrapper\gradle-wrapper.jar" ^
     "D:\Claude\LispIM\android-app\gradle\wrapper\gradle-wrapper.jar"
```

---

### 方案 3：使用已安装的 Gradle

如果你已经全局安装了 Gradle：

```bash
cd D:\Claude\LispIM\android-app
gradle wrapper --gradle-version 8.2
```

---

### 方案 4：手动下载（需要科学上网）

```bash
# 下载 gradle-wrapper.jar
curl -L "https://raw.githubusercontent.com/gradle/gradle/v8.2.0/gradle/wrapper/gradle-wrapper.jar" ^
     -o "D:\Claude\LispIM\android-app\gradle\wrapper\gradle-wrapper.jar"
```

或者使用浏览器下载：
- URL: `https://raw.githubusercontent.com/gradle/gradle/v8.2.0/gradle/wrapper/gradle-wrapper.jar`
- 保存到：`D:\Claude\LispIM\android-app\gradle\wrapper\gradle-wrapper.jar`

---

## 验证配置

配置完成后，验证是否可用：

```bash
cd D:\Claude\LispIM\android-app

# 检查 wrapper 是否工作
.\gradlew.bat --version

# 如果显示 Gradle 版本，说明配置成功
```

预期输出：
```
------------------------------------------------------------
Gradle 8.2
------------------------------------------------------------
Build time:   2023-06-30 18:02:30 UTC
Revision:     5f4a070a62a31a1e49cdc8ef97d37a77b5295e84

Kotlin:       1.8.20
Groovy:       3.0.17
Ant:          Apache Ant(TM) version 1.10.13
JVM:          21.0.x (Oracle Corporation 21.0.x+35-LTS-xxx)
OS:           Windows 10.0.22631
```

---

## 构建命令

配置成功后，使用以下命令构建：

```bash
cd D:\Claude\LispIM\android-app

# Debug 构建
.\gradlew.bat assembleDebug

# Release 构建
.\gradlew.bat assembleRelease

# 安装到连接的设备
.\gradlew.bat installDebug

# 清理并重新构建
.\gradlew.bat clean build
```

---

## 常见问题

### 问题 1： "Could not find gradle-wrapper.jar"
**解决**：确认文件存在于 `gradle/wrapper/` 目录

### 问题 2： "Connection timed out"
**解决**：使用方案 1（Android Studio）或方案 2（本地复制）

### 问题 3： "SDK not found"
**解决**：确认 `local.properties` 包含正确的 SDK 路径：
```
sdk.dir=D\:\\Claude\\Android
```

---

## 联系支持

如果以上方法都无法解决问题，请：
1. 确保已安装 Android Studio
2. 确保已安装 JDK 17 或 21
3. 确保环境变量 `ANDROID_HOME` 设置为 `D:\Claude\Android`

---

**最后更新**: 2026-03-17
