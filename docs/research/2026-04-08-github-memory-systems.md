# GitHub 记忆系统调研

面向对象：个人输入法工具 / 语音输入工具 / AI 辅助输入工具

调研时间：2026-04-08

## 1. 调研目标

这轮调研不直接做实现选型，而是先回答 3 个问题：

1. GitHub 上“前沿 AI 记忆系统”最近在往什么方向演进。
2. GitHub 上“个人知识库 / 外部记忆软件”有哪些稳定的产品模式值得借鉴。
3. 如果目标是做一款个人输入法工具，应该吸收哪些模式，避免哪些复杂度陷阱。

这里把“记忆系统”拆成两条线来看：

- `AI Agent / LLM Memory`：服务模型或 agent 的长期记忆、上下文管理、记忆提取、记忆检索。
- `PKM / External Memory`：服务人的外部记忆系统，强调捕获、编辑、整理、搜索、同步、归档。

结论先行：**这两类系统各自只解决了一半问题。**  
前者更强在自动化提取与低延迟召回，后者更强在用户可控、可编辑、可删除、可迁移。  
如果目标是个人输入法工具，最可能的正确方向不是二选一，而是做一个 **混合式记忆层**。

## 2. 调研方法与样本

本次主要阅读 GitHub 仓库主页与 README，优先选择“真正以记忆/知识管理为核心”的项目，而不是泛 AI 应用。

### 2.1 AI 记忆系统样本

- [mem0ai/mem0](https://github.com/mem0ai/mem0)
- [supermemoryai/supermemory](https://github.com/supermemoryai/supermemory)
- [mem9-ai/mem9](https://github.com/mem9-ai/mem9)
- [letta-ai/letta](https://github.com/letta-ai/letta)
- [langchain-ai/langmem](https://github.com/langchain-ai/langmem)
- [agentscope-ai/ReMe](https://github.com/agentscope-ai/ReMe)
- [getzep/graphiti](https://github.com/getzep/graphiti)
- [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)

补充参考：

- [getzep/zep](https://github.com/getzep/zep)
- [cpacker/MemGPT](https://github.com/cpacker/MemGPT)

### 2.2 PKM / 个人记忆软件样本

- [usememos/memos](https://github.com/usememos/memos)
- [logseq/logseq](https://github.com/logseq/logseq)
- [AppFlowy-IO/AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)
- [siyuan-note/siyuan](https://github.com/siyuan-note/siyuan)
- [silverbulletmd/silverbullet](https://github.com/silverbulletmd/silverbullet)
- [karakeep-app/karakeep](https://github.com/karakeep-app/karakeep)
- [toeverything/AFFiNE](https://github.com/toeverything/AFFiNE)
- [TriliumNext/Notes](https://github.com/TriliumNext/Notes)

### 2.3 样本规模说明

这不是“全量榜单”，而是“代表性架构样本”。

- AI 记忆系统这一侧，我刻意选了 7 种不同路线：
  - `memory + context engine`
  - `memory layer`
  - `shared persistent memory infrastructure`
  - `stateful agent memory`
  - `hot path + background memory`
  - `human-editable file memory`
  - `temporal graph memory`
  - `learning-oriented memory`
- PKM 这一侧，我刻意选了 7 种不同路线：
  - `quick capture timeline`
  - `graph / outliner`
  - `workspace / block database`
  - `block-level PKM`
  - `programmable markdown`
  - `archive + AI tagging`
  - `local-first canvas`

注：文中的 GitHub star 数是 2026-04-08 从仓库主页读取时的快照，只用于感知项目热度，不用于严格排名。

## 3. 快速结论

### 3.1 AI 记忆系统的前沿不再是“把聊天记录塞进向量库”

当前代表项目已经明显从“纯 embedding 检索”转向下面几类能力组合：

- `分层记忆`：区分 user / session / agent / persona / tool result。
- `热路径与后台分离`：低延迟召回走 hot path，记忆提取和整理在后台异步完成。
- `时间性`：记忆不是静态事实，而是有“何时成立、何时失效”的生命周期。
- `可追溯性`：记忆最好能追溯到原始 episode / 对话 / 文件来源。
- `混合检索`：vector + BM25 + graph traversal，而不是只做 semantic search。

### 3.2 人用记忆软件的竞争力不在“更聪明”，而在“更可控”

PKM / 外部记忆软件最稳定的产品原则反而很朴素：

- 捕获要快
- 编辑要直接
- 删除要明确
- 数据最好能导出
- 本地化或自托管让用户更敢存“真实信息”

这和 AI memory 的产品取向完全不同。  
AI memory 更倾向“自动写入、自动整合、自动召回”；  
PKM 更倾向“我知道记忆存在哪里，我可以自己改”。

### 3.3 对个人输入法工具，最有价值的是“混合式记忆层”

个人输入法工具的记忆需求同时具备这两个世界的特征：

- 它需要 AI memory 的 `低延迟召回` 与 `自动提炼`。
- 它又必须保留 PKM 的 `人工可见` 与 `人工可改`。

因此最可行的方向不是“直接接一个 agent memory 框架”，而是：

- 用 PKM 思路定义“用户可编辑的记忆面板”
- 用 AI memory 思路做“后台提炼、结构化、召回排序”

## 4. AI 记忆系统调研

### 4.1 总览

| 项目 | GitHub Stars | 核心定位 | 记忆模型 | 对输入法的启发 |
| --- | ---: | --- | --- | --- |
| [mem0](https://github.com/mem0ai/mem0) | 52,219 | 通用 memory layer | user / session / agent 多层记忆 | 适合做“统一记忆服务层” |
| [Supermemory](https://github.com/supermemoryai/supermemory) | 21,454 | memory + context engine | memory + profiles + RAG + connectors | 适合研究“记忆与上下文栈一体化” |
| [mem9](https://github.com/mem9-ai/mem9) | 907 | shared persistent memory infra | stateless plugins + central memory server + hybrid recall | 适合研究“跨设备 / 多客户端共享记忆” |
| [Letta](https://github.com/letta-ai/letta) | 21,935 | stateful agent 平台 | 显式 memory blocks + agent state | 适合研究“结构化人格 / 用户画像” |
| [LangMem](https://github.com/langchain-ai/langmem) | 1,382 | LangGraph 记忆工具包 | hot path + background manager | 适合研究“写入与召回解耦” |
| [ReMe](https://github.com/agentscope-ai/ReMe) | 2,636 | agent memory toolkit | 文件记忆 + 向量记忆 | 适合研究“可编辑记忆” |
| [Graphiti](https://github.com/getzep/graphiti) | 24,612 | temporal context graph | entities / facts / episodes / validity windows | 适合研究“记忆的时间性与冲突处理” |
| [Hindsight](https://github.com/vectorize-io/hindsight) | 7,805 | learning-oriented agent memory | world / experiences / mental models | 适合研究“让 agent 学，而不只是记” |

### 4.2 mem0

仓库：[mem0ai/mem0](https://github.com/mem0ai/mem0)

关键点：

- README 明确把自己定义成 `memory layer for personalized AI`。
- 强调 `Multi-Level Memory`，把记忆拆成 `User`、`Session`、`Agent` 三层。
- 提供清晰的写入 / 检索接口，例如 `mem0 add` 与 `mem0 search`。
- 同时支持 hosted 与 self-hosted 路线。

我认为它代表的是一种非常典型的“工程化 AI memory layer”思路：

- 先把“记忆”抽象成独立服务，而不是塞进 agent 主逻辑。
- 把记忆看成一种可检索资源，而不是整段上下文。
- 强调 token 成本和响应延迟，而不强调人类可读性。

优点：

- 抽象清晰，容易接入现有 AI 应用。
- 强调生产可用性，而不是论文 demo。
- 很适合拿来做“用户偏好 / 术语 / 历史事实”的统一记忆接口。

局限：

- 从 README 看，它更偏“服务层”和“平台层”，不是 end-user 可操作的记忆产品。
- 对个人输入法来说，如果直接照搬，容易得到一个“看不见也改不动”的黑盒记忆系统。

对输入法的启发：

- `多层记忆` 很值得借鉴。
- 个人输入法至少应区分：
  - `profile memory`
  - `session memory`
  - `terminology memory`
  - `episodic memory`

### 4.3 Supermemory

仓库：[supermemoryai/supermemory](https://github.com/supermemoryai/supermemory)

关键点：

- README 直接把自己定义成 `memory and context engine for AI`。
- 它把 `memory`、`user profiles`、`RAG`、`connectors` 和 `file processing` 放在同一系统里。
- 强调自动处理：
  - facts extraction
  - user profiles
  - knowledge updates and contradictions
  - expired information forgetting
- 支持 app、插件、MCP、API 多入口。

Supermemory 代表的是一种更“平台化”的前沿方向：**把记忆层、检索层、连接器层和用户画像层合并成统一 context stack。**

优点：

- 对开发者很有吸引力，因为接入成本低。
- 很适合跨应用、跨来源、跨会话持续积累上下文。
- `profile.static` 和 `profile.dynamic` 这种拆法，对输入法很有参考价值。

局限：

- 它的目标明显大于“输入法记忆”，属于更宽的 AI context infrastructure。
- 如果直接照抄，容易把一个轻量输入工具做成重型上下文平台。

对输入法的启发：

- 记忆系统不一定只处理“用户说过什么”，还可以统一处理：
  - 用户偏好
  - 最近动态上下文
  - 外部知识源
  - 文件和应用来源
- 但第一阶段没必要把 connectors 和 full RAG 一起上。

### 4.4 mem9

仓库：[mem9-ai/mem9](https://github.com/mem9-ai/mem9)

关键点：

- README 直接强调 `persistent memory across sessions and machines`。
- 它很明确地解决的是 coding agents 常见问题：
  - session 结束就失忆
  - 不同 agent 各自记忆孤岛
  - 记忆绑在本地文件和单台机器上
- 核心架构是：
  - `stateless agent plugins`
  - `central mnemo-server`
  - `shared memory pool`
  - `hybrid vector + keyword search`
  - `visual dashboard`
- 插件面向 Claude Code、OpenCode、OpenClaw 这类 agent 平台，所有客户端都通过同一个 server 共享记忆。

mem9 代表的是一种非常实用的路线：**客户端无状态，所有记忆集中到一层共享记忆服务。**

优点：

- 很适合跨设备、跨客户端、跨 agent 共享长期记忆。
- 记忆集中管理，便于做审计、权限、导出和统一治理。
- 对“一个人有多个 AI 入口”的场景非常有价值。

局限：

- 它的强项更偏 agent / coding workflow，而不是 end-user 记忆体验。
- 从当前 README 看，它更强调共享与基础设施，而不是复杂的学习式 memory reasoning。

对输入法的启发：

- 如果未来输入法工具要支持：
  - 多设备同步
  - 多客户端共享同一记忆
  - 桌面端 / 浏览器插件 / 命令行工具共用记忆
  - 团队或 workspace 级共享术语库
  那么 mem9 的 `stateless client + central memory server` 架构非常值得借鉴。

### 4.5 Letta

仓库：[letta-ai/letta](https://github.com/letta-ai/letta)

关键点：

- Letta 延续了 MemGPT 的核心方向，主打 `stateful agents`。
- README 里直接展示了 `memory_blocks` 的用法。
- 其核心不是“记多少”，而是“agent 是否拥有显式状态与持续身份”。

Letta 代表的是另一条路线：**把记忆直接建模成 agent 的可操作内部状态。**

优点：

- 适合复杂 agent，尤其是需要 persona / human profile / tool context 的系统。
- `memory_blocks` 这种显式结构，比“把所有记忆都做成向量”更容易控制。
- 很适合做“输入法助手”的固定角色设定，例如：
  - 你的职业背景
  - 你喜欢的表达方式
  - 不希望被翻译的术语

局限：

- 它更像完整 agent runtime 的一部分，不是轻量级输入法组件。
- 对个人输入法这种极低延迟产品来说，完整 stateful agent runtime 可能过重。

对输入法的启发：

- 用户画像不要只是一大段自由文本，应该允许拆成结构化 blocks。
- 比如：
  - `profession`
  - `tone_preference`
  - `bilingual_preference`
  - `forbidden_rewrites`
  - `preferred_terms`

### 4.6 LangMem

仓库：[langchain-ai/langmem](https://github.com/langchain-ai/langmem)

关键点：

- README 里最有价值的不是“存记忆”，而是 `hot path` 与 `background memory manager` 的分离。
- 它强调 agent 在当前对话里可以直接 `manage/search memory`。
- 同时也支持后台自动 `extract / consolidate / update`。

这是这轮调研里非常值得吸收的一点：**不要把“召回”和“整理”绑在同一个请求里。**

优点：

- 适合做低延迟产品。
- 写入、压缩、合并、修正可以放在后台跑。
- 对输入法这种实时交互工具非常有启发。

局限：

- 与 LangGraph 的耦合更强。
- 它提供的是机制，不是完整用户产品。

对输入法的启发：

- 每次输入时，热路径只拿：
  - 用户固定偏好
  - 高置信术语
  - 少量相关事实
- 输入结束后，后台再做：
  - 纠错归因
  - 术语抽取
  - 偏好更新
  - 冲突记忆合并

### 4.7 ReMe

仓库：[agentscope-ai/ReMe](https://github.com/agentscope-ai/ReMe)

关键点：

- ReMe 同时提供 `file-based` 与 `vector-based` 两种记忆系统。
- 它把“记忆作为文件”这件事讲得很清楚：`MEMORY.md`、日记文件、对话 JSONL、tool result 缓存。
- README 里明示 `semantic memory search = vector + BM25`。
- 它还非常重视 context compaction 和 tool result compaction。

ReMe 是这次调研里最像“AI memory 与人类可读记忆之间桥梁”的项目。

优点：

- 透明，记忆能直接看、直接改。
- 很适合把 agent 记忆变成“用户理解得了的东西”。
- 对输入法尤其重要，因为输入法记忆很容易触碰隐私和误记问题。

局限：

- 比通用云端 memory API 更偏系统化和工程化。
- 文件形态虽然透明，但在大规模情况下要考虑检索、同步与冲突管理。

对输入法的启发：

- 这是最值得借鉴的原型之一。
- 输入法记忆最好至少有一层是可编辑文件或可编辑记录，而不是只有 embedding。
- 对“最近纠错历史”“重要表达偏好”“高频术语”尤其合适。

### 4.8 Graphiti

仓库：[getzep/graphiti](https://github.com/getzep/graphiti)

关键点：

- Graphiti 把记忆建模成 `temporal context graph`。
- 核心概念包括：
  - `entities`
  - `facts / relationships`
  - `episodes`
  - `validity windows`
- 它特别强调：旧事实不是简单删除，而是 `invalidated`，保留时间历史与来源。
- 检索不是纯向量，而是 `semantic + BM25 + graph traversal` 的 hybrid retrieval。

这是目前最“前沿 AI memory”范式的一类：**记忆不是文档块，而是带时间维度的事实图。**

优点：

- 很适合处理会变化的偏好和事实。
- 比如用户今天说“保留英文术语”，以后又说“邮件里尽量中文化”，这种冲突不应该靠覆盖解决。
- provenance 很强，适合做审计和可解释性。

局限：

- 工程复杂度显著更高。
- 对个人输入法这种产品，除非未来要处理复杂的人物关系、任务状态、跨应用长期上下文，否则一开始上图记忆大概率过度设计。

对输入法的启发：

- `时间性` 值得学，`图数据库` 不一定要马上学。
- 一开始就可以在普通表结构里引入：
  - `valid_from`
  - `valid_to`
  - `source`
  - `confidence`
  - `last_confirmed_at`

### 4.9 Hindsight

仓库：[vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)

关键点：

- README 的核心表述很直接：`making agents that learn, not just remember`。
- 它把记忆分成三类：
  - `World`
  - `Experiences`
  - `Mental Models`
- API 也围绕这个目标设计成：
  - `retain`
  - `recall`
  - `reflect`
- `recall` 不是单一检索，而是并行跑：
  - semantic
  - keyword / BM25
  - graph
  - temporal

Hindsight 代表的是一个很值得注意的前沿方向：**把记忆系统从“存储与召回”进一步推到“反思与学习”。**

优点：

- 它比传统 memory layer 更强调 agent 从经验中形成更高阶理解。
- `reflect` 机制对长期行为修正和策略学习很有价值。
- 对复杂个人助理、自动化 agent、AI employee 这种场景尤其强。

局限：

- 对输入法这类高频、短链路、超低延迟工具来说，完整的 learning-style memory 很可能过重。
- `mental models` 这种抽象层如果没有好的解释界面，容易变成新的黑盒。

对输入法的启发：

- 值得借鉴的不是完整系统，而是 `reflect` 这个思想。
- 例如输入法可以在后台周期性反思：
  - 最近哪些纠错重复出现
  - 哪些术语稳定出现
  - 哪些表达偏好发生变化
  - 哪些记忆应该降权或过期

### 4.10 这一侧的综合判断

AI memory 当前最成熟的方向已经至少包括：

- `memory + context engine`
- `memory layer abstraction`
- `shared persistent memory infrastructure`
- `stateful structured memory`
- `hot path / background split`
- `human-editable memory`
- `temporal graph memory`
- `learning-oriented memory`

如果只让我保留两个最值得借鉴的点给个人输入法，我会选：

1. `LangMem` 的热路径 / 后台分离
2. `ReMe` 的可编辑记忆

如果再加两个面向未来的方向，则是：

3. `Graphiti` 的时间有效性建模
4. `Hindsight` 的反思式学习

### 4.11 横向全景图

这一节专门回答一个问题：**这些 AI memory 项目在功能上到底怎么分层，谁和谁是真竞争，谁和谁其实是在不同层。**

说明：

- 下面的横向对比基于项目 README 和公开文档里“明确强调”的能力整理。
- `未强调` 不等于完全不支持，只表示这不是它在仓库首页最核心的卖点。

#### 定位图

| 项目 | 更像什么 | 写入主路径 | 召回主路径 | 最强功能 | 主要代价 |
| --- | --- | --- | --- | --- | --- |
| [mem0](https://github.com/mem0ai/mem0) | 通用 memory layer | 对话 / messages 写入后抽取 | search + user/session/agent 记忆召回 | 多层记忆抽象清晰 | 人工可见性较弱 |
| [Supermemory](https://github.com/supermemoryai/supermemory) | 统一 context stack | 自动抽取 + connectors + files | profile + memories + RAG 一体查询 | 把 memory、profile、RAG、connectors 合成一层 | 系统边界大，容易偏重 |
| [mem9](https://github.com/mem9-ai/mem9) | 共享持久化记忆基础设施 | 插件自动保存 / API 写入 | 中央服务上的 hybrid recall | 跨设备、跨客户端、跨 agent 共享 | 更偏 infra，弱于高阶推理 |
| [Letta](https://github.com/letta-ai/letta) | stateful agent runtime | 显式 memory blocks / agent state | agent 依赖内部状态和工具 | 结构化 persona / human state | 更像完整 agent 平台 |
| [LangMem](https://github.com/langchain-ai/langmem) | 记忆工具包 | hot path 工具 + background manager | search/manage memory tools | 写入与整理彻底解耦 | 更依赖 LangGraph 生态 |
| [ReMe](https://github.com/agentscope-ai/ReMe) | 可编辑记忆管理器 | 文件摘要、压缩、持久化 | vector + BM25 + 文件检索 | 记忆透明、可读、可改 | 工程与文件治理成本较高 |
| [Graphiti](https://github.com/getzep/graphiti) | temporal context graph engine | ingest episodes / structured + unstructured data | semantic + keyword + graph + historical query | 时间有效性、provenance、关系检索 | 图模型复杂度高 |
| [Hindsight](https://github.com/vectorize-io/hindsight) | learning-oriented memory engine | retain 后抽取事实与经验 | recall + reflect | 从记忆走向“反思学习” | 对简单产品可能过重 |

#### 功能矩阵

| 项目 | 自动提炼 | 结构化画像 / 状态 | 共享 / 多客户端 | 混合检索 | 时间 / 冲突 | 人工可编辑 | 典型入口 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [mem0](https://github.com/mem0ai/mem0) | 强 | 强 | 中 | 未强调 | 未强调 | 弱 | SDK / API / CLI |
| [Supermemory](https://github.com/supermemoryai/supermemory) | 强 | 强 | 中 | 强 | 强 | 中 | App / MCP / API |
| [mem9](https://github.com/mem9-ai/mem9) | 中 | 弱 | 强 | 强 | 弱 | 中 | 插件 / Server / Dashboard |
| [Letta](https://github.com/letta-ai/letta) | 中 | 强 | 中 | 弱 | 弱 | 中 | CLI / API |
| [LangMem](https://github.com/langchain-ai/langmem) | 强 | 中 | 取决于存储层 | 中 | 弱 | 弱 | Tools / SDK |
| [ReMe](https://github.com/agentscope-ai/ReMe) | 强 | 中 | 弱 | 强 | 弱 | 强 | Files / Python API |
| [Graphiti](https://github.com/getzep/graphiti) | 强 | 中 | 中 | 强 | 强 | 弱 | SDK / MCP |
| [Hindsight](https://github.com/vectorize-io/hindsight) | 强 | 中 | 中 | 强 | 强 | 弱 | API / Server / UI |

#### 怎么读这张图

如果把这些项目放到一张架构图里，大致可以分成 4 组：

1. `通用服务层`
`mem0`、`Supermemory`、`mem9`

- 共同点：都想把记忆从 agent 主体里抽离出来，变成一层可复用服务。
- 差异：
  - `mem0` 更像标准 memory layer
  - `Supermemory` 更像 all-in-one context stack
  - `mem9` 更像 shared memory infra

2. `agent 内部记忆 / 工具层`
`Letta`、`LangMem`

- 共同点：都更贴近 agent runtime。
- 差异：
  - `Letta` 关注 stateful agent 本身
  - `LangMem` 关注如何给 agent 提供写入 / 搜索记忆的工具和后台管理器

3. `可控记忆层`
`ReMe`

- 它最特殊的地方是把 memory 做成可读可改的文件和记录，而不是纯黑盒存储。
- 对需要用户信任的产品尤其重要。

4. `前沿研究型记忆引擎`
`Graphiti`、`Hindsight`

- 共同点：都不满足于“记住文本块”。
- 差异：
  - `Graphiti` 走 `temporal graph + provenance`
  - `Hindsight` 走 `world / experiences / mental models + reflect`

#### 对个人输入法工具的 whole picture

如果把“个人输入法工具”放进去看，最关键的不是哪个项目最强，而是**你到底需要哪一层能力**：

- 如果你要的是 `基础记忆服务抽象`：看 `mem0`
- 如果你要的是 `全套上下文平台`：看 `Supermemory`
- 如果你要的是 `跨设备 / 多客户端共享`：看 `mem9`
- 如果你要的是 `agent 内部结构化状态`：看 `Letta`
- 如果你要的是 `热路径 / 后台异步整理`：看 `LangMem`
- 如果你要的是 `用户可见、可编辑、可删除`：看 `ReMe`
- 如果你要的是 `时间性与冲突有效期`：看 `Graphiti`
- 如果你要的是 `反思和学习机制`：看 `Hindsight`

对你们这个输入法工具，我的判断仍然是：

- 第一阶段最值得借鉴：`mem0 + LangMem + ReMe`
- 第二阶段再看：`mem9`
  当你们开始需要多设备或多客户端共享记忆
- 更后面的研究方向：`Graphiti + Hindsight`
  当你们真的遇到偏好冲突、复杂关系和长期策略学习问题

## 5. PKM / 外部记忆软件调研

### 5.1 总览

| 项目 | GitHub Stars | 核心定位 | 典型能力 | 对输入法的启发 |
| --- | ---: | --- | --- | --- |
| [Memos](https://github.com/usememos/memos) | 58,639 | quick capture timeline | Markdown、时间流、API、自托管 | 记忆捕获入口应该极轻 |
| [Logseq](https://github.com/logseq/logseq) | 41,930 | graph / outliner PKM | 双链、插件、DB graphs、RTC | 可把输入记忆组织成图谱而不是纯列表 |
| [AppFlowy](https://github.com/AppFlowy-IO/AppFlowy) | 69,370 | AI workspace | block + database + AI + self-host | 结构化编辑器很重要 |
| [SiYuan](https://github.com/siyuan-note/siyuan) | 42,411 | block-level PKM | 块引用、WYSIWYG、数据库、AI | 细粒度记忆编辑值得借鉴 |
| [SilverBullet](https://github.com/silverbulletmd/silverbullet) | 4,980 | programmable markdown PKM | Markdown space、Lua、查询 | 记忆系统可编程性很强 |
| [Karakeep](https://github.com/karakeep-app/karakeep) | 24,542 | archive + AI tagging | OCR、全文、AI 标签、收藏同步 | 捕获面与自动标签很适合个人输入工具扩展 |
| [AFFiNE](https://github.com/toeverything/AFFiNE) | 67,041 | local-first canvas workspace | docs + canvas + AI + sync | 多模态记忆工作台值得关注 |

### 5.2 Memos

仓库：[usememos/memos](https://github.com/usememos/memos)

关键点：

- 核心卖点非常聚焦：`quick capture`。
- README 直接强调：
  - `Timeline-first UI`
  - `Notes stored in Markdown`
  - `Zero telemetry`
  - `REST and gRPC APIs`

Memos 的价值不在“AI 多强”，而在于它把“我现在立刻记一条”这件事做到了极低阻力。

对输入法的启发：

- 记忆系统能不能成功，第一取决于 `capture friction`。
- 对个人输入法而言，最有价值的可能不是复杂 recall，而是：
  - 一键记住这次纠错
  - 一键记住这个术语
  - 一键把当前表达风格固定下来

### 5.3 Logseq

仓库：[logseq/logseq](https://github.com/logseq/logseq)

关键点：

- 强调 `privacy`、`longevity`、`user control`。
- 支持 `Markdown` / `Org-mode`。
- 有很强的 `plugin API`。
- 新的 DB version 开始把 graph、mobile、RTC sync 放进一个更统一的数据模型。

Logseq 代表的是“知识图谱式的个人记忆组织”。

对输入法的启发：

- 输入记忆不一定只能是“键值对偏好”。
- 还可以是：
  - 术语与项目的关系
  - 联系人与说话风格的关系
  - 应用场景与输出风格的关系

但 Logseq 的组织能力更适合“复盘”和“管理”，不适合每次输入热路径直接依赖。

### 5.4 AppFlowy

仓库：[AppFlowy-IO/AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)

关键点：

- 明确定位为 `AI workspace`。
- 强调 `data privacy first` 和 `100% control of your data`。
- 同时是 block editor、database、协作空间和 AI 工作台。

AppFlowy 的启发不是“怎么做记忆检索”，而是：**记忆需要结构化编辑界面。**

对输入法的启发：

- 以后如果输入法记忆越来越复杂，只靠 textarea 不够。
- 需要把记忆拆成可管理对象：
  - 术语表
  - 风格规则
  - 场景模板
  - app-specific 记忆
  - 联系人 / 群聊上下文

### 5.5 SiYuan

仓库：[siyuan-note/siyuan](https://github.com/siyuan-note/siyuan)

关键点：

- 强调 `privacy-first personal knowledge management`。
- 支持 `block-level reference`、`Markdown WYSIWYG`、`database`、`flashcard`、`AI writing and Q/A chat`。
- 很典型的“块级 PKM”产品。

对输入法的启发：

- 记忆粒度越细，越容易被用户接受。
- 与其让用户维护一大段“记忆描述”，不如让他维护几十条小 memory items。
- 这与当前仓库中 `memoryProfile` 大文本的做法相比，是明显更可扩展的方向。

### 5.6 SilverBullet

仓库：[silverbulletmd/silverbullet](https://github.com/silverbulletmd/silverbullet)

关键点：

- 定位非常鲜明：`Programmable`、`Private`、`Self Hosted`。
- 内容是 Markdown Pages。
- 支持双链、Objects、Queries、Lua 脚本和自定义命令。

SilverBullet 代表的是一种很适合高阶用户的路线：**记忆系统本身是可编程的。**

对输入法的启发：

- 如果未来产品定位偏“高级用户工具”，可以开放：
  - 自定义记忆规则
  - 自定义召回优先级
  - 自定义清洗 / 归档脚本

但这不适合当第一版核心能力。

### 5.7 Karakeep

仓库：[karakeep-app/karakeep](https://github.com/karakeep-app/karakeep)

关键点：

- 它不是传统笔记，而是 `bookmark-everything`。
- 非常强调：
  - `full text search`
  - `AI automatic tagging and summarization`
  - `OCR`
  - `full page archival`
  - `browser bookmarks sync`
  - `highlights`
  - `self-hosting first`

Karakeep 最大的价值是说明：**现代个人记忆系统越来越多来自“被动捕获”和“多源归档”，不是手写笔记。**

对输入法的启发：

- 输入法未来的记忆来源不应该只有“用户手动填写”。
- 还可以来自：
  - 用户纠错历史
  - 高频短语
  - 剪贴板片段
  - 选中的文本
  - 常见外文术语
  - 浏览器 / 聊天 / 文档场景中的高频表达

### 5.8 AFFiNE

仓库：[toeverything/AFFiNE](https://github.com/toeverything/AFFiNE)

关键点：

- 明确强调 `privacy-focused`、`local-first`、`real-time collaborative`。
- Docs、canvas、tables、AI 在同一工作台里融合。
- 上游依赖里直接强调 CRDT 与 local-first 数据引擎。

对输入法的启发：

- 如果未来记忆系统不只是“后台能力”，还需要一个真正可视化的工作台，AFFiNE 的方向值得借鉴。
- 但这更偏“记忆管理产品界面”，不是输入热路径能力。

## 6. 两类系统的本质区别

| 维度 | AI Memory | PKM / External Memory |
| --- | --- | --- |
| 主要服务对象 | agent / LLM | 用户本人 |
| 主要目标 | 让模型更会记、更会召回 | 让用户更会存、更会找、更敢用 |
| 写入方式 | 自动提取为主 | 手动输入为主，AI 辅助 |
| 检索方式 | semantic / graph / hybrid | full-text / browse / timeline / graph |
| 数据透明度 | 往往较低 | 往往较高 |
| 编辑与删除 | 常常不是核心能力 | 必须是一等公民 |
| 延迟目标 | 很低，通常在推理链路中 | 中等，可接受更慢查询 |
| 工程复杂度 | 中高 | 中等，重点在 UX 和数据模型 |
| 对输入法的价值 | 热路径召回、自动学习 | 用户控制、信任、纠错闭环 |

一句话概括：

- AI memory 解决“系统怎么替你记”
- PKM 解决“你怎么知道系统记了什么”

个人输入法工具需要两者同时成立。

## 7. 当前前沿模式

### 7.1 分层记忆

前沿系统几乎都不再把记忆当成一个桶。

更常见的拆法是：

- `profile memory`
- `session memory`
- `episodic memory`
- `semantic / fact memory`
- `tool / artifact memory`

这对输入法尤为关键，因为输入法里“固定偏好”和“本次上下文”绝不能混在一起。

### 7.2 热路径与后台整理分离

这是最值得借鉴的模式之一。

- 热路径负责低延迟召回
- 后台任务负责抽取、压缩、去重、冲突消解、长期归档

对输入法来说，如果把“抽取新记忆”放在每次输入的同步路径里，很快就会卡死体验。

### 7.3 记忆需要时间性

Graphiti 的最大启发不是图，而是时间。

很多偏好是会变化的：

- 以前保留英文术语，现在希望中文化
- 以前喜欢短句，现在希望更自然
- 某个项目名已经弃用

因此长期记忆至少需要基本的时间字段和失效机制。

### 7.4 透明性和可编辑性正在回归

ReMe、Memos、SilverBullet 这类项目都说明了一件事：  
用户愿意让系统记住更多东西的前提，是他看得见、改得动、删得掉。

对个人输入法来说，这几乎不是加分项，而是必要条件。

### 7.5 混合检索优于纯向量检索

本轮样本里已经多次出现：

- vector
- BM25
- keyword
- graph traversal
- exact match

原因很简单：

- 术语记忆需要 exact match
- 风格偏好需要 semantic similarity
- 多轮事实关系需要结构化关系检索

输入法工具尤其不能只依赖 embedding。

### 7.6 记忆入口比记忆模型更决定成败

Memos、Karakeep 很能说明这一点。

如果写入入口足够轻，人会持续喂系统真实数据。  
如果写入入口很重，再强的 memory engine 也会饿死。

## 8. 对个人输入法工具的直接启发

### 8.1 最值得做的不是“万能记忆”，而是 4 层记忆

如果目标是个人输入法工具，我建议把记忆最小化为 4 层：

1. `固定画像层`
职业、常见场景、表达风格、语言偏好、禁用改写规则。

2. `术语层`
品牌名、项目名、模型名、缩写、高优先级中英混输词表。

3. `情景层`
最近 N 次输入、当前 app、当前窗口、最近复制内容、最近纠错内容。

4. `长期事实层`
从多次输入与纠错中沉淀出来的稳定偏好与高价值事实。

### 8.2 应该默认“用户能改”

个人输入法的记忆如果不可见，用户迟早会因为一次误记而彻底失去信任。

因此记忆条目至少应该具备：

- 查看
- 编辑
- 暂停启用
- 删除
- 标记为固定
- 查看来源

### 8.3 最适合第一阶段借鉴的组合

如果从这轮 GitHub 调研里抽一个最现实的组合，我会这样组合：

- `Memos` 的轻量捕获
- `ReMe` 的可编辑长期记忆
- `LangMem` 的热路径 / 后台分离
- `mem0` 的多层记忆抽象

而不是一开始就上：

- 完整图记忆
- 完整 agent runtime
- 大而全知识库工作台

### 8.4 不建议第一阶段直接采用的方向

#### 方向一：直接做图数据库式记忆

原因：

- 对当前输入法工具来说，复杂度明显过高。
- 用户当前最痛的问题更可能是术语、风格、短期场景，而不是复杂实体关系推理。

#### 方向二：完全依赖自动抽取

原因：

- 自动抽取会误记。
- 输入法是高频工具，误记的伤害会非常高。
- 必须保留人工可控入口。

#### 方向三：把记忆只做成一大段 profile 文本

原因：

- 难编辑、难召回、难解释、难逐步演化。
- 这只适合 very early prototype，不适合长期产品。

## 9. 面向本仓库的研究性建议

当前仓库已经有两个非常自然的起点：

- `memoryProfile`
- `terminologyGlossary`

这说明产品已经有“用户背景”和“术语增强”的雏形。下一步不一定要引入外部大框架，而可以沿下面这条路线演化：

### Phase A：把自由文本记忆拆成结构化条目

从：

- 一大段 `memoryProfile`

演化到：

- `profession`
- `style_preferences[]`
- `do_not_translate_terms[]`
- `preferred_output_modes[]`
- `forbidden_transformations[]`

### Phase B：加入情景记忆和纠错记忆

增加：

- 最近纠错条目
- 高置信用户术语
- app-specific 记忆
- 最近会话摘要

### Phase C：后台提炼长期事实

在不影响热路径延迟的前提下，后台生成：

- 常用表达偏好
- 高重复术语
- 冲突规则提示
- 记忆失效候选

### Phase D：再考虑时间性和图结构

只有当系统开始出现大量“偏好冲突”“跨项目上下文”“联系人 / 场景关系”的时候，再考虑 Graphiti 一类思路。

## 10. 我认为最值得持续跟踪的仓库

### AI memory

- [mem0ai/mem0](https://github.com/mem0ai/mem0)
  - 看工程化 memory layer 的抽象与成本优化。
- [supermemoryai/supermemory](https://github.com/supermemoryai/supermemory)
  - 看 memory、profiles、RAG、connectors 如何合并成统一 context stack。
- [mem9-ai/mem9](https://github.com/mem9-ai/mem9)
  - 看 stateless plugins + central memory server 的共享记忆基础设施。
- [langchain-ai/langmem](https://github.com/langchain-ai/langmem)
  - 看 hot path / background memory 的演进。
- [agentscope-ai/ReMe](https://github.com/agentscope-ai/ReMe)
  - 看 file-based memory 和可编辑 memory 的产品化路径。
- [getzep/graphiti](https://github.com/getzep/graphiti)
  - 看 temporal memory 与事实失效机制。
- [letta-ai/letta](https://github.com/letta-ai/letta)
  - 看 stateful agent memory 的结构化建模。
- [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)
  - 看反思式 learning memory 与多通路 recall。

### PKM / external memory

- [usememos/memos](https://github.com/usememos/memos)
  - 看 quick capture 与轻量记忆 UX。
- [karakeep-app/karakeep](https://github.com/karakeep-app/karakeep)
  - 看 archive、OCR、AI tagging、多源捕获。
- [logseq/logseq](https://github.com/logseq/logseq)
  - 看 graph / plugin / DB graph 演化。
- [siyuan-note/siyuan](https://github.com/siyuan-note/siyuan)
  - 看 block-level PKM 与本地化产品策略。
- [toeverything/AFFiNE](https://github.com/toeverything/AFFiNE)
  - 看 local-first 协作和可视化工作台。

## 11. 最终判断

如果目标是“给个人输入法工具增加记忆能力”，本轮 GitHub 调研得出的最核心判断是：

**不要把记忆系统理解成单一数据库或单一检索器。**  
它更像一个组合层：

- 面向用户：必须可见、可改、可删、可停用
- 面向模型：必须可检索、可压缩、可分层、可低延迟召回
- 面向产品：必须有轻量写入口，且默认隐私友好

更具体地说：

- `AI memory` 提供了召回和自动提炼能力
- `PKM` 提供了信任、可控和长期使用习惯
- `个人输入法工具` 应该把两者嫁接起来

所以这类产品最值得追求的不是“最聪明的 AI 记忆”，而是：

**一个低延迟、可编辑、分层、隐私友好的个人记忆层。**

## 12. 参考仓库

- [mem0ai/mem0](https://github.com/mem0ai/mem0)
- [supermemoryai/supermemory](https://github.com/supermemoryai/supermemory)
- [mem9-ai/mem9](https://github.com/mem9-ai/mem9)
- [letta-ai/letta](https://github.com/letta-ai/letta)
- [langchain-ai/langmem](https://github.com/langchain-ai/langmem)
- [agentscope-ai/ReMe](https://github.com/agentscope-ai/ReMe)
- [getzep/graphiti](https://github.com/getzep/graphiti)
- [vectorize-io/hindsight](https://github.com/vectorize-io/hindsight)
- [getzep/zep](https://github.com/getzep/zep)
- [cpacker/MemGPT](https://github.com/cpacker/MemGPT)
- [usememos/memos](https://github.com/usememos/memos)
- [logseq/logseq](https://github.com/logseq/logseq)
- [AppFlowy-IO/AppFlowy](https://github.com/AppFlowy-IO/AppFlowy)
- [siyuan-note/siyuan](https://github.com/siyuan-note/siyuan)
- [silverbulletmd/silverbullet](https://github.com/silverbulletmd/silverbullet)
- [karakeep-app/karakeep](https://github.com/karakeep-app/karakeep)
- [toeverything/AFFiNE](https://github.com/toeverything/AFFiNE)
- [TriliumNext/Notes](https://github.com/TriliumNext/Notes)
