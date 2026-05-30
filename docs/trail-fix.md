# Trail 拖尾修复说明

本文档解释 `scenes/unit/players/trail.gd` 的修改，以及为什么原来的 Trail 会越跑越偏。

---

## 一、现象

向下移动后按空格 dash，Trail 轨迹会逐渐偏到角色 Sprite **下方**，移动得越远，偏移越大。

---

## 二、根本原因：坐标系混用

Godot 里同一个点有两种常见表示方式：

| 名称 | 含义 | 例子 |
|------|------|------|
| **世界坐标** (`global_position`) | 相对于整个场景原点的位置 | 角色在地图上的 (100, 500) |
| **本地坐标** (`position` / `points`) | 相对于**当前节点自己**的位置 | 在 Line2D 里画在 (0, 0) 的点 |

`Line2D` 的 `points` 属性要求的是**本地坐标**——即「相对于这条线自己的原点」来画。

### 旧代码的问题

```gdscript
points_array.append(player.global_position)  # 存的是世界坐标
points = points_array                        # 却直接当本地坐标用
```

相当于：你告诉画笔「在纸上画 (100, 500)」，但画笔以为你说的是「从笔尖往右 100、往下 500」。角色越往下走，世界坐标的 Y 越大，Trail 在本地坐标里就被画得越靠下，偏移不断累积。

### 为什么 `top_level = true` 让问题更明显

在 `player_well_rounded.tscn` 里，Trail 节点设置了 `top_level = true`：

- Trail **不再**跟随父节点 `Visuals` 的变换（缩放、位移）
- 它的 `global_position` 需要代码自己维护
- 场景里还写了 `position = Vector2(0, -30)`，与 Sprite 的实际位置 `(1, -62)` 也不一致

旧代码既没有同步 Trail 的位置，又把世界坐标直接塞进 `points`，所以偏差会随移动距离放大。

---

## 三、修复思路（三句话）

1. **记录位置时**：用 `player.sprite.global_position`（Sprite 的世界坐标），而不是 `player.global_position`（角色根节点），这样 Trail 对齐的是**可见的角色**，不是碰撞体中心。
2. **每帧同步**：把 Trail 的 `global_position` 设到当前 Sprite 位置（锚点 `anchor`）。
3. **画线之前**：用 `to_local()` 把历史世界坐标转成 Trail 的本地坐标，再赋给 `points`。

---

## 四、逐行解释代码

### 成员变量

```gdscript
var points_array: Array[Vector2] = []
```

- **作用**：在内存里保存 Trail 经过的每一个**世界坐标**点。
- **为什么单独存**：`Line2D.points` 每帧都要根据当前 Trail 位置重新换算成本地坐标；我们先把「真实轨迹」存在 `points_array`，再转换后写入 `points`。
- **`Array[Vector2]`**：Godot 4 的强类型数组，元素只能是 `Vector2`。

```gdscript
var is_active := false
```

- **作用**：Trail 是否正在记录。
- **`true`**：dash 开始，`start_trail()` 里设为 `true`，`_process` 每帧追加点。
- **`false`**：计时结束或尚未 dash，`_process` 开头直接 `return`，不做任何事。

---

### `_process`：每帧更新拖尾

```gdscript
func _process(_delta: float) -> void:
```

- Godot 每帧调用一次。参数 `delta` 是上一帧到这一帧的秒数。
- 写成 `_delta`（前面加下划线）表示：**这个函数里用不到 delta**，只是满足 `_process` 的函数签名。这是 GDScript 的常见写法，不是语法错误。

```gdscript
if not is_active:
    return
```

未激活时不记录、不画线。

```gdscript
var anchor := player.sprite.global_position
```

- `anchor`：本帧 Trail 的**锚点**，即 Sprite 当前在世界中的位置。
- `:=` 是类型推断赋值，等价于 `var anchor: Vector2 = ...`。

```gdscript
points_array.append(anchor)
if points_array.size() > trail_length:
    points_array.pop_front()
```

- 每帧在数组**末尾**加入当前位置。
- 超过 `trail_length`（默认 25）时，从**开头**删掉最老的点 → 得到固定长度的拖尾。

```gdscript
global_position = anchor
```

把 Trail 节点整体移到 Sprite 位置。之后 `to_local()` 的参考原点就是「当前 Sprite 所在处」。

```gdscript
var local_points := PackedVector2Array()
local_points.resize(points_array.size())
for i in points_array.size():
    local_points[i] = to_local(points_array[i])
points = local_points
```

| 行 | 含义 |
|----|------|
| `PackedVector2Array()` | Godot 内置的高效向量数组，`Line2D.points` 需要的类型 |
| `resize(n)` | 预分配 n 个空位，避免循环里反复扩容 |
| `to_local(世界坐标)` | 把世界坐标转成「相对于当前 Trail 节点」的本地坐标 |
| `points = local_points` | 交给 Line2D 真正绘制 |

**举例**：若 Trail 在 (100, 200)，历史点里有 (98, 200)，则 `to_local` 后约为 `(-2, 0)`——在 Trail 本地「左边 2 像素」，画出来就是正确的拖尾形状。

---

### `start_trail`：dash 开始时

```gdscript
func start_trail() -> void:
    is_active = true
    clear_points()
    points_array.clear()
    global_position = player.sprite.global_position
    trail_timer.start(trail_duration)
```

- 清空旧点和旧数组，避免上次 dash 的残留。
- **立刻**设置 `global_position`，避免 dash 第一帧 Trail 还在旧位置。
- 启动 `TrailTimer`，`trail_duration` 秒后触发 `_on_trail_timer_timeout`，关闭拖尾。

---

## 五、修改前后对比

### 旧代码（有问题）

```gdscript
func _process(delta: float) -> void:
    if not is_active:
        return

    points_array.append(player.global_position)   # ① 用的是 Player 根节点，不是 Sprite
    if points_array.size() > trail_length:
        points_array.pop_front()

    points = points_array                            # ② 世界坐标直接当本地坐标
```

### 新代码（修复后）

```gdscript
func _process(_delta: float) -> void:
    if not is_active:
        return

    var anchor := player.sprite.global_position      # ① 对齐 Sprite
    points_array.append(anchor)
    if points_array.size() > trail_length:
        points_array.pop_front()

    global_position = anchor                           # ② 同步 Trail 节点位置
    var local_points := PackedVector2Array()
    local_points.resize(points_array.size())
    for i in points_array.size():
        local_points[i] = to_local(points_array[i])  # ③ 世界 → 本地
    points = local_points
```

| 对比项 | 旧 | 新 |
|--------|----|----|
| 记录谁的位置 | `player.global_position` | `player.sprite.global_position` |
| Trail 节点位置 | 不更新 | 每帧 `global_position = anchor` |
| 写入 `points` | 直接存世界坐标 | `to_local()` 转换后再写入 |

---

## 六、数据流简图

```
每帧 _process（is_active == true）
        │
        ▼
读取 Sprite 世界坐标 → anchor
        │
        ├──► points_array 追加 anchor（世界坐标历史）
        │
        ├──► global_position = anchor（移动 Trail 节点）
        │
        └──► 对每个历史点 to_local() → points（Line2D 绘制）
```

---

## 七、相关场景配置（供参考）

`player_well_rounded.tscn` 中 Trail 节点：

- `top_level = true` — 独立世界变换，位置由脚本维护
- `parent = Visuals` — 逻辑上挂在视觉节点下
- `position = Vector2(0, -30)` — 场景里的初始偏移；运行后会被 `global_position = anchor` 覆盖

若修复后仍有极轻微偏差，可在编辑器里把 Trail 的 `position` 改为 `(0, 0)`，或删除该偏移，因为位置已由代码每帧同步。

---

## 八、涉及文件

| 文件 | 变更 |
|------|------|
| `scenes/unit/players/trail.gd` | 坐标转换与 Sprite 锚点逻辑 |
| `scenes/player_well_rounded.tscn` | Trail 节点配置（`top_level`、Line2D 参数） |
| `scenes/player.gd` | dash 时调用 `trail.start_trail()`（未改逻辑，仅关联） |
