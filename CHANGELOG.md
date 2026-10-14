# Changelog

本文件记录工程级显著变更，格式遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)。

## [Unreleased]

### Added

- 工程基线初始化（P1–P5，2026-10-15）：
  - 目录骨架（pages/components/model/data/ai/mock/utils/design/common）与架构契约 `Docs/ARCHITECTURE.md`（目录职责/依赖方向/§5.4 差异/命名规范/UI 约定）
  - 技术栈版本锁定 `Docs/TECH_STACK.md`（API 26 / DevEco 26.0.0.851 / hvigor 6.26.8，运行时零依赖基线）
  - 配置层与环境隔离：`common/constants/BuildConfig.ets`、`common/config/ApiConfig.ets`、`common/config/MockConfig.ets`，`.gitignore` 增补签名/密钥防线
  - 日志与错误基线：`common/logger/Logger.ets`（YouJing. 前缀、IS_DEBUG 门控）、`common/error/AppError.ets`、`common/error/ErrorCode.ets`（1xxx–4xxx 区段 14 码），EntryAbility.onError 接入
  - 设计 tokens：`design/ColorTokens|SpaceTokens|FontTokens|MotionTokens.ets`（占位基线值，待 UI 设计定稿替换）
