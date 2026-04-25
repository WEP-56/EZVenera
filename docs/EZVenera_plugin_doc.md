# EZVenera 插件制作文档

更新时间：2026-04-25

本文面向想为 EZVenera 编写或移植漫画源插件的开发者。目标不是解释原版 Venera 的全部能力，而是说明 EZVenera 当前真实可用的插件能力、字段格式、常见坑和调试方式。

---

## 1. 先理解 EZVenera 插件是什么

EZVenera 的插件本质上是一个 `.js` 文件。宿主会用内置的 JavaScript 运行时加载这个文件，找到：

```js
class YourSource extends ComicSource { ... }
```

然后实例化，并从这个实例上读取它支持的能力。

EZVenera 的插件格式尽量兼容原项目 `venera-configs`，但只实现简化版产品真正保留的部分。结论很直接：

- 宿主已支持的字段：会解析并参与实际功能。
- 宿主未支持的字段：通常会被忽略，不会自动报错。
- 这意味着“能安装”不等于“所有能力都能在 EZVenera 中生效”。

---

## 2. 插件文件放在哪里，如何安装

### 2.1 运行时存储位置

EZVenera 会把安装后的插件保存到应用支持目录下的：

```text
plugin_runtime/sources/*.js
```

对应实现：

- `lib/src/plugin_runtime/plugin_runtime.dart`
- `lib/src/plugin_runtime/repository/plugin_source_repository.dart`

同一目录下还会保存：

- `plugin_runtime/data/*.json`
  - 每个源自己的持久化数据
- `plugin_runtime/cookies.db`
  - 插件请求使用的 cookie

### 2.2 UI 安装入口

宿主当前支持两种安装方式：

1. 在“源管理”页面直接填 `.js` 原始地址安装
2. 从源索引列表中选中某个插件再安装

对应页面：

- `lib/src/pages/sources_page.dart`

---

## 3. EZVenera 当前支持哪些插件能力

这是写文档前最重要的边界。

### 3.1 已支持

- 基础元数据
  - `name`
  - `key`
  - `version`
  - `minAppVersion`
  - `url`
- 账号
  - `account.login`
  - `account.loginWithWebview`
  - `account.loginWithCookies`
  - `account.logout`
  - `account.registerWebsite`
- 搜索
  - `search.load`
  - `search.loadNext`
  - `search.optionList`
  - `search.enableTagsSuggestions`
  - `search.onTagSuggestionSelected`
- 分类
  - `category`
  - `categoryComics.load`
  - `categoryComics.optionList`
  - `categoryComics.optionLoader`
  - `categoryComics.ranking.load`
  - `categoryComics.ranking.loadNext`
  - `categoryComics.ranking.loadWithNext`
- 漫画详情与阅读
  - `comic.loadInfo`
  - `comic.loadEp`
  - `comic.onImageLoad`
  - `comic.onThumbnailLoad`
  - `comic.link`
  - `comic.idMatch`
- 设置
  - `select`
  - `switch`
  - `input`
- 本地化
  - `translation`

### 3.2 当前未接入或不要依赖

- `explore`
- `favorites`
- `comic.loadComments`
- `comic.sendComment`
- `comic.loadChapterComments`
- `comic.sendChapterComment`
- `comic.likeComic`
- `comic.likeComment`
- `comic.voteComment`
- `comic.starRating`
- `comic.archive`
- 设置项 `callback`
- `comic.onClickTag`
- `comic.enableTagsTranslate`
- `comic.loadThumbnails`

### 3.3 关于 `minAppVersion`

请照实填写 `minAppVersion`。EZVenera 当前会读取这个字段，也会把真实宿主版本暴露给 JS 的 `APP.version`，但安装阶段还没有像原版那样做严格拦截，所以不要把它当成唯一兼容性保护。

---

## 4. 插件最小结构

一个最小可用插件至少要满足：

1. 有合法的 `name`、`key`
2. 至少提供一个入口
   - `search`
   - 或 `category + categoryComics`
3. 提供 `comic.loadInfo`
4. 提供 `comic.loadEp`

最小示例：

```js
/** @type {import('./_venera_.js')} */

class DemoSource extends ComicSource {
    name = "示例漫画源"
    key = "demo_source"
    version = "1.0.0"
    minAppVersion = "1.2.2"
    url = "https://example.com/demo_source.js"

    search = {
        load: async (keyword, options, page) => {
            return {
                comics: [
                    new Comic({
                        id: "demo-1",
                        title: `搜索：${keyword}`,
                        subTitle: "第一个结果",
                        cover: "https://example.com/cover.jpg",
                        tags: ["demo", "sample"],
                        description: "这是一个最小搜索结果示例"
                    })
                ],
                maxPage: 1
            }
        }
    }

    comic = {
        loadInfo: async (id) => {
            return new ComicDetails({
                title: "示例漫画",
                subTitle: "最小详情页",
                cover: "https://example.com/cover.jpg",
                description: "用于说明 ComicDetails 的基本结构",
                tags: {
                    genre: ["demo", "tutorial"]
                },
                chapters: {
                    "ep-1": "第 1 话"
                }
            })
        },

        loadEp: async (comicId, epId) => {
            return {
                images: [
                    "https://example.com/page-1.jpg",
                    "https://example.com/page-2.jpg"
                ]
            }
        }
    }
}
```

---

## 5. 基础元数据字段

### 5.1 `name`

显示在源管理页和其他 UI 中的名称。

```js
name = "JM 漫画"
```

### 5.2 `key`

源的唯一标识，要求：

- 只能是字母、数字、下划线
- 不能和已安装源重复

```js
key = "jm"
```

### 5.3 `version`

插件自己的版本号。主要用于展示和更新。

```js
version = "1.0.3"
```

### 5.4 `minAppVersion`

声明最低宿主版本。

```js
minAppVersion = "1.2.2"
```

### 5.5 `url`

插件更新地址。EZVenera 的“更新源”会用它重新下载插件文件。

```js
url = "https://example.com/raw/demo_source.js"
```

---

## 6. 宿主提供的 JS API

EZVenera 通过 `assets/init.js` 注入了一套 JS helper。当前真正应该依赖的主要是：

- `Network`
- `fetch`
- `Convert`
- `HtmlDocument`
- `Comic`
- `ComicDetails`
- `ImageLoadingConfig`
- `Image`
- `APP`
- `setClipboard`
- `getClipboard`
- `compute`

### 6.1 `Network`

最常用的网络 API。支持：

- `Network.get`
- `Network.post`
- `Network.put`
- `Network.patch`
- `Network.delete`
- `Network.fetchBytes`
- `Network.setCookies`
- `Network.getCookies`
- `Network.deleteCookies`

示例：

```js
let res = await Network.get(
    "https://example.com/search?q=test",
    {
        "user-agent": "Mozilla/5.0",
        "referer": "https://example.com/"
    }
)

if (res.status !== 200) {
    throw `HTTP ${res.status}`
}

let json = JSON.parse(res.body)
```

### 6.2 `fetch`

如果你更习惯浏览器风格，也可以用 `fetch`：

```js
let res = await fetch("https://example.com/api/list", {
    method: "GET",
    headers: {
        "user-agent": "Mozilla/5.0"
    }
})

if (!res.ok) {
    throw `HTTP ${res.status}`
}

let json = await res.json()
```

### 6.3 `Convert`

常用编码、哈希、AES、RSA 都在这里。典型用途：

- `Convert.encodeUtf8`
- `Convert.decodeUtf8`
- `Convert.encodeBase64`
- `Convert.decodeBase64`
- `Convert.md5`
- `Convert.sha1`
- `Convert.sha256`
- `Convert.hmac`

示例：

```js
let raw = Convert.encodeUtf8("comic-123")
let hash = Convert.md5(raw)
let hashText = Convert.hexEncode(hash)
```

### 6.4 `HtmlDocument`

用于解析 HTML、按 CSS 选择器取元素。

示例：

```js
let res = await Network.get("https://example.com/comic/123")
let doc = new HtmlDocument(res.body)

let title = doc.querySelector("h1")?.text ?? "未知标题"
let items = doc.querySelectorAll(".chapter-item")
```

### 6.5 `Comic`

搜索结果、分类结果中返回的每一项都应该是 `new Comic({...})`。

常用字段：

- `id`
- `title`
- `subTitle`
- `cover`
- `tags`
- `description`
- `maxPage`
- `language`
- `favoriteId`
- `stars`

示例：

```js
return new Comic({
    id: comic.id.toString(),
    title: comic.title,
    subTitle: comic.author ?? "",
    cover: comic.cover,
    tags: comic.tags ?? [],
    description: comic.intro ?? ""
})
```

### 6.6 `ComicDetails`

详情页返回值，通常由 `comic.loadInfo` 返回。

常用字段：

- `title`
- `subTitle`
- `cover`
- `description`
- `tags`
- `chapters`
- `subId`
- `thumbnails`
- `url`
- `maxPage`

示例：

```js
return new ComicDetails({
    title: detail.title,
    subTitle: detail.author,
    cover: detail.cover,
    description: detail.description,
    tags: {
        author: [detail.author],
        genre: detail.tags
    },
    chapters: {
        "ep-1": "第 1 话",
        "ep-2": "第 2 话"
    },
    url: detail.url
})
```

### 6.7 `APP`

当前实用的三个属性：

- `APP.version`
- `APP.locale`
- `APP.platform`

示例：

```js
if (APP.platform === "windows") {
    // 可按平台切换域名或请求头
}
```

### 6.8 `UI`

`init.js` 里有 `UI.showMessage`、`UI.showDialog`、`UI.launchUrl` 等声明，但 EZVenera 当前宿主没有把这套 UI bridge 真正实现出来。也就是说：

- 你能调用
- 但不要把它当成当前 EZVenera 可靠可用的能力

写新插件时，不要把主流程建立在 `UI.*` 上。

---

## 7. 搜索能力

EZVenera 搜索支持两种模型：

1. `search.load(keyword, options, page)`
2. `search.loadNext(keyword, options, nextToken)`

如果同时存在，宿主优先使用 `search.load`。

### 7.1 页码搜索

```js
search = {
    optionList: [
        {
            label: "排序",
            type: "select",
            options: [
                "latest-最新",
                "popular-热门"
            ],
            default: "latest"
        }
    ],

    load: async (keyword, options, page) => {
        let sort = options[0] ?? "latest"
        let res = await Network.get(
            `https://example.com/api/search?q=${encodeURIComponent(keyword)}&sort=${sort}&page=${page}`
        )
        let json = JSON.parse(res.body)

        return {
            comics: json.items.map(item => new Comic({
                id: item.id.toString(),
                title: item.title,
                subTitle: item.author ?? "",
                cover: item.cover,
                tags: item.tags ?? [],
                description: item.intro ?? ""
            })),
            maxPage: json.maxPage ?? 1
        }
    }
}
```

### 7.2 next-token 搜索

```js
search = {
    loadNext: async (keyword, options, next) => {
        let url = next
            ? `https://example.com/api/search/next?token=${encodeURIComponent(next)}`
            : `https://example.com/api/search?q=${encodeURIComponent(keyword)}`

        let res = await Network.get(url)
        let json = JSON.parse(res.body)

        return {
            comics: json.items.map(item => new Comic({
                id: item.id.toString(),
                title: item.title,
                cover: item.cover
            })),
            next: json.nextToken ?? null
        }
    }
}
```

### 7.3 搜索标签建议

可选支持：

- `search.enableTagsSuggestions`
- `search.onTagSuggestionSelected(namespace, tag)`

这个功能只建议在源本身就有明确标签系统时使用。

---

## 8. 分类能力

分类页分成两层：

1. `category`
   - 用来定义页面上的分类入口
2. `categoryComics`
   - 用来加载某个分类下的漫画列表

### 8.1 `category`

支持三种 part：

- `fixed`
- `random`
- `dynamic`

示例：

```js
category = {
    title: "分类",
    enableRankingPage: true,
    parts: [
        {
            name: "题材",
            type: "fixed",
            categories: [
                {
                    label: "热血",
                    target: {
                        page: "category",
                        attributes: {
                            category: "hot_blood",
                            param: null
                        }
                    }
                },
                {
                    label: "恋爱",
                    target: {
                        page: "category",
                        attributes: {
                            category: "romance",
                            param: null
                        }
                    }
                }
            ]
        },
        {
            name: "今日随机",
            type: "random",
            randomNumber: 5,
            categories: [
                {
                    label: "编辑推荐",
                    target: {
                        page: "search",
                        attributes: {
                            keyword: "editor"
                        }
                    }
                }
            ]
        }
    ]
}
```

### 8.2 `categoryComics.load`

这是分类漫画页的主入口：

```js
categoryComics = {
    load: async (category, param, options, page) => {
        let sort = options[0] ?? "latest"
        let res = await Network.get(
            `https://example.com/api/category?name=${category}&sort=${sort}&page=${page}`
        )
        let json = JSON.parse(res.body)

        return {
            comics: json.items.map(item => new Comic({
                id: item.id.toString(),
                title: item.title,
                cover: item.cover,
                subTitle: item.author ?? ""
            })),
            maxPage: json.maxPage ?? 1
        }
    }
}
```

### 8.3 静态分类选项：`optionList`

```js
categoryComics = {
    optionList: [
        {
            label: "排序",
            options: [
                "latest-最新",
                "popular-热门",
                "update-更新"
            ]
        },
        {
            label: "状态",
            options: [
                "all-全部",
                "ongoing-连载中",
                "completed-已完结"
            ],
            notShowWhen: ["special"]
        }
    ],
    load: async (category, param, options, page) => {
        // options[0], options[1] 分别对应上面两个选项组
    }
}
```

### 8.4 动态分类选项：`optionLoader`

如果某个分类的筛选项要根据分类本身动态返回，可以用：

```js
categoryComics = {
    optionLoader: async (category, param) => {
        if (category === "rank") {
            return [
                {
                    label: "时间",
                    options: [
                        "day-日榜",
                        "week-周榜",
                        "month-月榜"
                    ]
                }
            ]
        }

        return [
            {
                label: "排序",
                options: [
                    "latest-最新",
                    "popular-热门"
                ]
            }
        ]
    },

    load: async (category, param, options, page) => {
        // ...
    }
}
```

EZVenera 当前已经支持 `optionLoader`，但如果你不需要动态行为，优先用更简单的 `optionList`。

### 8.5 排行页：`ranking`

EZVenera 当前支持两种排行分页模型：

1. `ranking.load(option, page)`
2. `ranking.loadNext(option, nextToken)`

同时也兼容原模板常见的：

3. `ranking.loadWithNext(option, nextToken)`

页码示例：

```js
categoryComics = {
    ranking: {
        options: [
            "day-日榜",
            "week-周榜"
        ],
        load: async (option, page) => {
            let res = await Network.get(
                `https://example.com/api/ranking?mode=${option}&page=${page}`
            )
            let json = JSON.parse(res.body)
            return {
                comics: json.items.map(item => new Comic({
                    id: item.id.toString(),
                    title: item.title,
                    cover: item.cover
                })),
                maxPage: json.maxPage ?? 1
            }
        }
    }
}
```

next-token 示例：

```js
categoryComics = {
    ranking: {
        options: [
            "hot-热门"
        ],
        loadNext: async (option, next) => {
            let url = next
                ? `https://example.com/api/ranking/next?token=${encodeURIComponent(next)}`
                : `https://example.com/api/ranking?mode=${option}`

            let res = await Network.get(url)
            let json = JSON.parse(res.body)

            return {
                comics: json.items.map(item => new Comic({
                    id: item.id.toString(),
                    title: item.title,
                    cover: item.cover
                })),
                next: json.nextToken ?? null
            }
        }
    }
}
```

---

## 9. 详情页与章节页

### 9.1 `comic.loadInfo`

这是 EZVenera 的详情页核心。

返回数据时最关键的是：

- 标题
- 封面
- 标签
- 章节

章节可以是两种结构。

#### 结构 A：平铺章节

```js
chapters: {
    "ep-1": "第 1 话",
    "ep-2": "第 2 话"
}
```

#### 结构 B：分组章节

```js
chapters: {
    "单行本": {
        "v1": "第 1 卷",
        "v2": "第 2 卷"
    },
    "番外": {
        "extra-1": "番外 1"
    }
}
```

完整示例：

```js
comic = {
    loadInfo: async (id) => {
        let res = await Network.get(`https://example.com/api/comic/${id}`)
        let data = JSON.parse(res.body)

        return new ComicDetails({
            title: data.title,
            subTitle: data.author,
            cover: data.cover,
            description: data.description,
            tags: {
                author: [data.author],
                status: [data.status],
                genre: data.tags ?? []
            },
            chapters: Object.fromEntries(
                data.chapters.map(chapter => [chapter.id.toString(), chapter.title])
            ),
            url: data.url
        })
    }
}
```

### 9.2 `comic.loadEp`

章节页只需要返回图片 URL 列表：

```js
comic = {
    loadEp: async (comicId, epId) => {
        let res = await Network.get(
            `https://example.com/api/comic/${comicId}/episode/${epId}`
        )
        let json = JSON.parse(res.body)

        return {
            images: json.images.map(item => item.url)
        }
    }
}
```

---

## 10. 图片链路：`onImageLoad` / `onThumbnailLoad`

很多插件写到这里最容易出问题。

### 10.1 什么时候需要 `onImageLoad`

当图片请求不是“直接 GET 一张公开 URL”时，你才需要它。常见场景：

- 图片请求需要额外 headers
- 需要 Referer
- 需要 cookie
- 需要 POST 请求拿图
- 需要对响应做解密/解码
- 图片本身是乱序图，需要解扰
- 第一次请求失败后需要重新签名 URL

### 10.2 返回值格式

`onImageLoad` 应返回一个对象，宿主会把它当作 `ImageLoadingConfig` 解析。常用字段：

- `url`
- `method`
- `data`
- `headers`
- `onResponse`
- `modifyImage`
- `onLoadFailed`

示例：

```js
comic = {
    onImageLoad: async (url, comicId, epId) => {
        return {
            url: url,
            headers: {
                "referer": "https://example.com/",
                "user-agent": "Mozilla/5.0"
            }
        }
    }
}
```

### 10.3 `onThumbnailLoad`

和 `onImageLoad` 类似，但用于封面或缩略图。

```js
comic = {
    onThumbnailLoad: (url) => {
        return {
            url,
            headers: {
                "referer": "https://example.com/"
            }
        }
    }
}
```

EZVenera 现在详情页和本地页的远程封面也会走这个链路，所以如果封面加载要特殊 headers，不要只写 `onImageLoad`，最好也补 `onThumbnailLoad`。

### 10.4 `onResponse`

当服务端返回的不是可以直接显示的图片字节时，用 `onResponse`。

示例：

```js
comic = {
    onImageLoad: async (url, comicId, epId) => {
        return {
            url,
            onResponse: async (buffer) => {
                // buffer 是 ArrayBuffer / Uint8Array 风格的二进制数据
                // 这里可以解密、解压、裁切头部等
                return buffer
            }
        }
    }
}
```

要求：

- 返回值必须还是图片字节
- 最稳妥的是直接返回原 buffer 或处理后的 buffer

### 10.5 `modifyImage`

如果图像像 JM 一样需要“解扰”，用 `modifyImage`。它不是函数对象，而是一段 JS 脚本文本。脚本内部必须定义：

```js
let modifyImage = (image) => { ... }
```

示例：

```js
comic = {
    onImageLoad: async (url, comicId, epId) => {
        return {
            url,
            modifyImage: `
                let modifyImage = (image) => {
                    let topHalf = image.copyRange(0, 0, image.width, Math.floor(image.height / 2))
                    let bottomHalf = image.copyRange(
                        0,
                        Math.floor(image.height / 2),
                        image.width,
                        image.height - Math.floor(image.height / 2)
                    )
                    let result = Image.empty(image.width, image.height)
                    result.fillImageAt(0, 0, bottomHalf)
                    result.fillImageAt(0, bottomHalf.height, topHalf)
                    return result
                }
            `
        }
    }
}
```

可用的 `Image` API：

- `image.width`
- `image.height`
- `image.copyRange(x, y, width, height)`
- `image.copyAndRotate90()`
- `image.fillImageAt(x, y, anotherImage)`
- `image.fillImageRangeAt(x, y, anotherImage, srcX, srcY, width, height)`
- `Image.empty(width, height)`

### 10.6 `onLoadFailed`

如果第一次加载图片失败，需要重新生成 URL 或重新取签名，可以用它。

```js
comic = {
    onImageLoad: async (url, comicId, epId) => {
        return {
            url,
            headers: {
                "referer": "https://example.com/"
            },
            onLoadFailed: async () => {
                let retryUrl = await this.getSignedImageUrl(comicId, epId)
                return {
                    url: retryUrl,
                    headers: {
                        "referer": "https://example.com/"
                    }
                }
            }
        }
    }
}
```

EZVenera 当前会对阅读图片保留有限次数的失败回退，不需要你在插件里自己写一个死循环。

---

## 11. 账号登录与 cookie

EZVenera 支持三种登录形态：

1. 账号密码登录
2. WebView 登录
3. 手工输入 cookie 登录

### 11.1 账号密码登录

```js
account = {
    login: async (account, pwd) => {
        let res = await Network.post(
            "https://example.com/api/login",
            {
                "content-type": "application/json"
            },
            JSON.stringify({
                account,
                password: pwd
            })
        )

        let json = JSON.parse(res.body)
        if (json.code !== 200) {
            throw json.message ?? "登录失败"
        }

        this.saveData("token", json.token)
        return "ok"
    },

    logout: () => {
        this.deleteData("token")
        Network.deleteCookies("https://example.com")
    }
}
```

宿主行为：

- `account.login` 成功后，EZVenera 会自动保存传入的账号密码用于重登
- 你自己的 token、session、用户偏好等，仍然要自己 `saveData`

### 11.2 WebView 登录

```js
account = {
    loginWithWebview: {
        url: "https://example.com/login",
        checkStatus: (url, title) => {
            return url.startsWith("https://example.com/user")
        },
        onLoginSuccess: () => {
            // 可选：补做一些登录完成后的初始化
        }
    },

    logout: () => {
        Network.deleteCookies("https://example.com")
    }
}
```

宿主会在 WebView 登录成功后自动保存 cookie，本地 `localStorage` 也会落到源数据里。

### 11.3 cookie 登录

```js
account = {
    loginWithCookies: {
        fields: ["sessionid", "csrftoken"],
        validate: async (values) => {
            Network.setCookies("https://example.com", [
                new Cookie({
                    name: "sessionid",
                    value: values[0],
                    domain: ".example.com"
                }),
                new Cookie({
                    name: "csrftoken",
                    value: values[1],
                    domain: ".example.com"
                })
            ])

            let res = await Network.get("https://example.com/api/me")
            return res.status === 200
        }
    },

    logout: () => {
        Network.deleteCookies("https://example.com")
    }
}
```

---

## 12. 设置项

EZVenera 当前只支持三种设置类型：

- `select`
- `switch`
- `input`

示例：

```js
settings = {
    domain: {
        title: "站点域名",
        type: "select",
        options: [
            { value: "https://a.example.com", text: "主站 A" },
            { value: "https://b.example.com", text: "主站 B" }
        ],
        default: "https://a.example.com"
    },

    useMobileApi: {
        title: "使用移动接口",
        type: "switch",
        default: true
    },

    customToken: {
        title: "自定义令牌",
        type: "input",
        default: "",
        validator: "value.length > 0 ? null : '不能为空'"
    }
}
```

读取方式：

```js
let domain = this.loadSetting("domain") || "https://a.example.com"
let useMobileApi = this.loadSetting("useMobileApi")
let customToken = this.loadSetting("customToken")
```

注意：

- `callback` 类型在 EZVenera 当前会被忽略
- 如果设置值影响请求域名、headers、排序等，请在每次真实请求前读取，不要只在构造时读一次

---

## 13. `translation`、`idMatch`、`link`

### 13.1 `translation`

用于翻译源自己的字符串。

```js
translation = {
    "zh_CN": {
        "Latest": "最新",
        "Popular": "热门"
    },
    "zh_TW": {
        "Latest": "最新",
        "Popular": "熱門"
    }
}
```

你也可以在源内部用：

```js
this.translate("Latest")
```

### 13.2 `comic.idMatch`

用于识别用户输入是否像一个漫画 ID。

```js
comic = {
    idMatch: "^(\\d+|demo-\\d+)$"
}
```

### 13.3 `comic.link`

让宿主能把外部链接转换成漫画 ID。

```js
comic = {
    link: {
        domains: [
            "example.com",
            "www.example.com"
        ],
        linkToId: (url) => {
            let match = url.match(/comic\\/(\\d+)/)
            return match ? match[1] : null
        }
    }
}
```

---

## 14. 一个更完整的示例插件

下面这个例子同时演示：

- 搜索
- 分类
- 详情
- 章节
- 设置
- 图片 headers
- 链接识别

```js
/** @type {import('./_venera_.js')} */

class SampleSource extends ComicSource {
    name = "Sample Source"
    key = "sample_source"
    version = "1.0.0"
    minAppVersion = "1.2.2"
    url = "https://example.com/sample_source.js"

    settings = {
        baseUrl: {
            title: "站点地址",
            type: "select",
            options: [
                { value: "https://api.example.com", text: "主站" },
                { value: "https://backup.example.com", text: "备用站" }
            ],
            default: "https://api.example.com"
        }
    }

    get baseUrl() {
        return this.loadSetting("baseUrl") || "https://api.example.com"
    }

    search = {
        optionList: [
            {
                label: "排序",
                options: [
                    "latest-最新",
                    "popular-热门"
                ]
            }
        ],
        load: async (keyword, options, page) => {
            let sort = options[0] ?? "latest"
            let res = await Network.get(
                `${this.baseUrl}/search?q=${encodeURIComponent(keyword)}&sort=${sort}&page=${page}`
            )
            let json = JSON.parse(res.body)
            return {
                comics: json.items.map(item => this.parseComic(item)),
                maxPage: json.maxPage ?? 1
            }
        }
    }

    category = {
        title: "分类",
        parts: [
            {
                name: "题材",
                type: "fixed",
                categories: [
                    {
                        label: "动作",
                        target: {
                            page: "category",
                            attributes: {
                                category: "action",
                                param: null
                            }
                        }
                    },
                    {
                        label: "校园",
                        target: {
                            page: "category",
                            attributes: {
                                category: "school",
                                param: null
                            }
                        }
                    }
                ]
            }
        ]
    }

    categoryComics = {
        optionList: [
            {
                label: "排序",
                options: [
                    "latest-最新",
                    "popular-热门"
                ]
            }
        ],
        load: async (category, param, options, page) => {
            let sort = options[0] ?? "latest"
            let res = await Network.get(
                `${this.baseUrl}/category/${category}?sort=${sort}&page=${page}`
            )
            let json = JSON.parse(res.body)
            return {
                comics: json.items.map(item => this.parseComic(item)),
                maxPage: json.maxPage ?? 1
            }
        }
    }

    comic = {
        loadInfo: async (id) => {
            let res = await Network.get(`${this.baseUrl}/comic/${id}`)
            let data = JSON.parse(res.body)
            return new ComicDetails({
                title: data.title,
                subTitle: data.author,
                cover: data.cover,
                description: data.description,
                tags: {
                    author: [data.author],
                    genre: data.tags ?? []
                },
                chapters: Object.fromEntries(
                    data.chapters.map(ch => [ch.id.toString(), ch.title])
                ),
                url: data.url
            })
        },

        loadEp: async (comicId, epId) => {
            let res = await Network.get(`${this.baseUrl}/comic/${comicId}/episode/${epId}`)
            let data = JSON.parse(res.body)
            return {
                images: data.images
            }
        },

        onImageLoad: async (url, comicId, epId) => {
            return {
                url,
                headers: {
                    "referer": `${this.baseUrl}/comic/${comicId}`,
                    "user-agent": "Mozilla/5.0"
                }
            }
        },

        onThumbnailLoad: (url) => {
            return {
                url,
                headers: {
                    "referer": this.baseUrl,
                    "user-agent": "Mozilla/5.0"
                }
            }
        },

        idMatch: "^sample-\\d+$",

        link: {
            domains: ["example.com"],
            linkToId: (url) => {
                let match = url.match(/comic\\/(sample-\\d+)/)
                return match ? match[1] : null
            }
        }
    }

    parseComic(item) {
        return new Comic({
            id: item.id.toString(),
            title: item.title,
            subTitle: item.author ?? "",
            cover: item.cover,
            tags: item.tags ?? [],
            description: item.description ?? ""
        })
    }
}
```

---

## 15. 常见坑

### 15.1 `loadInfo` 和 `loadEp` 不是独立的

很多源的章节 ID、图片签名、请求 Referer 都依赖详情页数据。即使 `loadEp` 能单独拿图，也建议保证：

- `loadInfo` 能拿到稳定章节结构
- `loadEp` 不依赖页面上偶然存在的临时状态

### 15.2 `onImageLoad` 返回值不是随便什么都行

最稳妥的返回格式就是普通对象：

```js
return {
    url: "...",
    headers: {...},
    onResponse: async (buffer) => buffer,
    onLoadFailed: async () => ({ url: "..." })
}
```

不要返回宿主不认识的复杂类实例。

### 15.3 `modifyImage` 是脚本文本，不是直接传函数对象

错误写法：

```js
modifyImage: (image) => image
```

正确写法：

```js
modifyImage: `
    let modifyImage = (image) => {
        return image
    }
`
```

### 15.4 需要 headers 的封面不要只写 `onImageLoad`

现在详情页封面、部分本地页远程封面也会走缩略图链路。要是封面图需要 Referer 或 cookie，请同时实现：

- `comic.onImageLoad`
- `comic.onThumbnailLoad`

### 15.5 cookie 登录别忘了 `logout`

如果只实现登录不实现退出，宿主层面的“已退出”与网络层 cookie 会不一致，用户会遇到“看起来退出了，实际上请求还带 cookie”的混乱状态。

### 15.6 `UI.*` 不要当作主流程依赖

当前 EZVenera 的 UI bridge 没有真正接通。写插件时不要把：

- `UI.showDialog`
- `UI.showInputDialog`
- `UI.launchUrl`

当作关键业务步骤。

---

## 16. 调试建议

### 16.1 先分层定位

推荐按这个顺序排：

1. `search` 是否能拿到正确 JSON
2. `Comic` 字段是否组装正确
3. `loadInfo` 是否能拿到稳定章节
4. `loadEp` 是否能拿到原始图片 URL 列表
5. 只有在第 4 步通过后，再看 `onImageLoad`
6. 只有在第 5 步通过后，再看 `modifyImage`

### 16.2 避免一次写太多

写新源时建议顺序：

1. 先把 `search.load` 跑通
2. 再补 `comic.loadInfo`
3. 再补 `comic.loadEp`
4. 最后才处理图片 headers、cookie、解扰

### 16.3 先返回最小数据

比如详情页调不通时，先返回最小 `ComicDetails`：

```js
return new ComicDetails({
    title: "test",
    cover: "",
    tags: {},
    chapters: {
        "1": "第 1 话"
    }
})
```

只要最小结构能被宿主接受，再逐项加字段。

### 16.4 隔离 `modifyImage`

如果怀疑是解扰脚本问题：

1. 先让 `onImageLoad` 只返回 `headers`
2. 暂时去掉 `modifyImage`
3. 确认能看到“原始错图”
4. 再单独恢复 `modifyImage`

这样最容易判断到底是：

- 请求失败
- 返回数据不对
- 还是解扰逻辑错了

---

## 17. 当前实现参考文件

阅读这几个文件，最能帮助你理解 EZVenera 的真实插件行为：

- `lib/src/plugin_runtime/plugin_runtime.dart`
- `lib/src/plugin_runtime/parser/plugin_source_parser.dart`
- `lib/src/plugin_runtime/engine/plugin_js_engine.dart`
- `lib/src/plugin_runtime/models.dart`
- `lib/src/plugin_runtime/services/plugin_image_loader.dart`
- `lib/src/plugin_runtime/services/plugin_image_modifier.dart`
- `assets/init.js`

推荐一起对照：

- `D:\venera\EZVenera-config\_template_.js`
- `D:\venera\EZVenera-config\_venera_.js`
- `D:\venera\EZVenera-config\jm.js`

---

## 18. 最后的写法建议

如果你是给 EZVenera 单独写新插件，建议把优先级定成：

1. 搜索或分类入口稳定
2. 详情页结构稳定
3. 阅读图片链路稳定
4. 设置项简单、明确
5. 能不用 `onImageLoad` 就不用
6. 能不用 `modifyImage` 就不用

原因很简单：宿主最稳定的主路径就是“搜索 / 分类 -> 详情 -> 阅读 / 下载”。插件越贴这条主路径，维护成本越低。
