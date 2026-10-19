# 契约 v1（冻结于 <commit sha>）

> 冻结后任何分支不得修改。改契约只能由主控执行，改完必须广播，并在每个在跑的 worktree 里 `git merge main`。

## 接口

```
GET  /api/items?q=&page=   →  { items: Item[], total: number }
  错误: 400 INVALID_QUERY | 404 NOT_FOUND | 500 UPSTREAM_DOWN

POST /api/items            ←  { title: string }  →  { id: string }
  错误: 400 EMPTY_TITLE | 409 DUPLICATE
```

约定：

- 所有错误响应统一信封 `{ code: string, message: string }`，`code` 为大写下划线常量。
- 分页参数 `page` 从 1 开始；非法值返回 400，不静默回落到 1。
- 时间字段一律 ISO 8601 字符串，UTC，带 `Z`。

## 数据模型

```sql
items(
  id          text        primary key,
  title       text        not null,
  created_at  timestamptz not null default now()
)
idx_items_created_at (created_at desc)
```

约定：

- 主键一律 `text`（业务侧生成），不用自增。
- 表名、字段名一律 snake_case。
- 所有表必须带 `created_at`。

## 共享类型

```ts
// shared/types/item.ts —— 冻结文件
export type Item = {
  id: string;
  title: string;
  createdAt: string;
};
```

约定：

- 前端不得自行定义 `Item` 的变体，一律从这里 import。
- 序列化后字段为 camelCase，数据库为 snake_case，转换在 API 层做一次。

## 变更记录

| 版本 | commit | 变更 | 影响波次 |
|---|---|---|---|
| v1 | `<sha>` | 初始冻结 | 1、2 |
