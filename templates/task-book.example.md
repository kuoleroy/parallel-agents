# 任务书 02 · 搜索接口

- 分支：feature/search
- worktree：/Users/me/proj-wk-search
- 波次：2
- 前置：任务 01（数据层）已合并；契约 v1 已冻结
- 上游契约：docs/contracts/v1.md @ 3f9a1c2
- 分配端口：3102（起服务只用这个端口，别抢 3000/5432 这类公共端口）

## 目标

让前端能按关键词分页检索条目，支持空结果与上游故障降级。

## 独占文件

- src/api/search.ts
- src/api/__tests__/search.test.ts

## 不要动

- src/db/**（任务 01 的边界）
- shared/types/**（冻结）
- migrations/**（冻结）
- package.json / pnpm-lock.yaml（冻结，依赖已预装）
- docker-compose.yml（冻结）

## 步骤

> 环境：依赖已由主控预装；不要自己起服务、不要抢端口。数据库已在 5432 就绪。

1. 在 `src/api/search.ts` 实现 `GET /api/items`，参数 `q`、`page`。
2. 参数校验：`page` 非正整数 → `400 INVALID_QUERY`，响应体 `{ code, message }`。
3. 查询走 `idx_items_created_at`，按 `created_at desc` 排序。
4. 上游查询抛错时返回 `500 UPSTREAM_DOWN`，不得把原始错误栈透出。
5. 空结果返回 `{ items: [], total: 0 }`，不是 404。
6. 字段按契约做 snake_case → camelCase 转换。

## 验收标准

- [ ] `pnpm test src/api/__tests__/search.test.ts` 全绿
- [ ] `pnpm build` 退出码 0，无 TS error
- [ ] `curl -s "localhost:3102/api/items?q=abc" | jq '.total'` 为数字
- [ ] `curl -s -o /dev/null -w '%{http_code}' "localhost:3102/api/items?page=abc"` → `400`
- [ ] `curl -s "localhost:3102/api/items?page=abc" | jq -r .code` → `INVALID_QUERY`
- [ ] 停掉数据库后同端点返回 `500`，body 含 `UPSTREAM_DOWN`
- [ ] `git diff main -- src/db/` 为空

## 注意

- 新增依赖必须成熟且许可宽松（MIT / Apache-2.0）；能不新增就不新增
- 验收由主控在干净栈执行
- 完工必须产出交付契约（见下）

## 交付契约（完工后填写）

- 改动文件：
- 自测命令与结果：
- 对契约的实现情况：
- 遗留隐患：
- 下游须知：


