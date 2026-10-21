/**
 * 文件说明：全应用共用的基础 UI 组件库。
 *
 * 主要组件：
 *  - PageHeader：页面标题栏（返回键 + 标题/副标题 + 右侧操作区）；
 *  - IconBtn / ActionButton：图标按钮、胶囊按钮；
 *  - Tag / ChipGroup / Segmented：标签、横向单选筛选条、分段选择器；
 *  - StateView：加载中 / 空 / 错误占位；
 *  - SearchBox / Field / SwitchRow / NavRow：搜索框、带标签输入框、开关行、可点击设置行；
 *  - CardGroup / StatTile：圆角卡片分组（可折叠）、概览页数字卡片；
 *  - ConnBanner：连接失败 / 登录失效横幅。
 * 使用位置：几乎所有 views/*.ets 与 pages/*.ets，以及 components/ServerForm.ets。
 * 约定：颜色一律取自 Store.palette()，跟随深浅色与主题色；可点击区域不小于 40vp（应用市场会检测过小热区）；
 *   卡片类组件使用半透明底色 + backdropBlur 实现毛玻璃，模糊半径由 Store.blurRadius() 决定（关闭时为 0）。
 */
import { t, tf } from '../common/I18n';
import { Store } from '../common/Store';
import { withAlpha } from '../common/Theme';

/**
 * Shared building blocks. All colors come from Store.palette() so light/dark and the accent follow the settings.
 * Touch targets are at least 40 vp (AppGallery checks small hot zones).
 */

// ------------------------------------------------------------------ header

/** Page header height without the status bar */
// 中文：标题栏高度（不含状态栏），Index 的侧栏顶部也用它对齐
export const HEADER_H: number = 48;

/** Page header: optional back button, title + subtitle and trailing actions */
// 中文：页面标题栏组件。topInset 为 true 时自行加上状态栏高度（页面沉浸式绘制到屏幕顶部）。
// 右侧操作区通过尾随闭包 @BuilderParam actions 传入，通常放若干 IconBtn。
@ComponentV2
export struct PageHeader {
  // 全局 Store：调色板与安全区高度 safeTop
  private store: Store = Store.get();
  // 标题（单行省略）
  @Param title: string = '';
  // 副标题，空串时不显示
  @Param subtitle: string = '';
  // 是否显示返回按钮；显示时标题字号略小（17 vs 20），符合二级页面层级
  @Param showBack: boolean = false;
  /** Adds the status bar height on top (pages drawn edge to edge) */
  // 中文：是否叠加状态栏高度（嵌在已处理安全区的容器里时传 false）
  @Param topInset: boolean = true;
  // 锁定：右侧操作区整体置灰且不可点击（当前登录账号无此分区权限时使用），返回按钮不受影响
  @Param locked: boolean = false;
  // 点击返回按钮的回调，一般调用 store.pop()
  @Event onBack: () => void = () => {
  };

  // 中文：默认的空操作区 Builder（@BuilderParam 需要一个默认值）
  @Builder
  noActions() {
  }

  // 右侧操作区，使用方以尾随闭包 PageHeader({...}) { IconBtn(...) } 传入
  @BuilderParam actions: () => void = this.noActions;

  build() {
    Row() {
      if (this.showBack) {
        IconBtn({
          icon: $r('sys.symbol.chevron_left'), label: t('返回'), iconSize: 22, onTap: () => {
            this.onBack();
          }
        })
      }
      Column() {
        Text(this.title)
          .fontSize(this.showBack ? 17 : 20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.palette().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(this.store.palette().subtle)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showBack ? 2 : 6 })

      Row({ space: 2 }) {
        this.actions()
      }
      .enabled(!this.locked)
      .opacity(this.locked ? 0.4 : 1)
    }
    .width('100%')
    .height(HEADER_H + (this.topInset ? this.store.safeTop : 0))
    .padding({ left: this.showBack ? 4 : 12, right: 8, top: this.topInset ? this.store.safeTop : 0 })
    .alignItems(VerticalAlign.Center)
  }
}

// ------------------------------------------------------------------ buttons

// 中文：圆形图标按钮（默认 44×44vp 热区）。
// 重要注意：不要在 IconBtn 上 .bindMenu()！IconBtn 内部 Stack 自带 onClick，点击会被子组件的 onClick 吞掉，
// 外部绑定的菜单不会弹出。需要弹出菜单的按钮请直接写 Stack + SymbolGlyph 并在其上 .bindMenu(...)
// （参见 pages/EditorPage.ets、pages/LogPage.ets、views/FilesView.ets 中的写法）。
@ComponentV2
export struct IconBtn {
  private store: Store = Store.get();
  // 图标（HarmonyOS Symbol 资源，如 $r('sys.symbol.plus')）
  @Param icon: Resource = $r('sys.symbol.dot_grid_2x2');
  // icon 是 media 里的单色 SVG（如 $r('app.media.ic_ssh')）而不是系统 Symbol 时设为 true；用 fillColor 着色
  @Param svg: boolean = false;
  // 无障碍朗读文本（屏幕阅读器读出），图标按钮没有可见文字，务必填写
  @Param label: string = '';
  // 图标字号（vp）
  @Param iconSize: number = 20;
  // 图标颜色，空串使用主文字色
  @Param color: string = '';
  // 是否可用；false 时半透明（0.4）且点击无效
  @Param active: boolean = true;
  // 忙碌中：显示加载圈替代图标，并忽略点击，防止重复操作
  @Param busy: boolean = false;
  /** Touch target edge (dp) */
  // 中文：触摸区边长，默认 44vp 以满足应用市场的最小热区检查
  @Param box: number = 44;
  // 点击回调（仅在 active 且非 busy 时触发）
  @Event onTap: () => void = () => {
  };

  build() {
    Stack() {
      if (this.busy) {
        LoadingProgress().width(22).height(22).color(this.store.palette().accentUi)
      } else if (this.svg) {
        Image(this.icon)
          .width(this.iconSize)
          .height(this.iconSize)
          .objectFit(ImageFit.Contain)
          .fillColor(this.color.length > 0 ? this.color : this.store.palette().text)
          .draggable(false)
      } else {
        SymbolGlyph(this.icon)
          .fontSize(this.iconSize)
          .fontColor([this.color.length > 0 ? this.color : this.store.palette().text])
      }
    }
    .width(this.box)
    .height(this.box)
    .borderRadius(this.box / 2)
    .opacity(this.active ? 1 : 0.4)
    .accessibilityText(this.label)
    .onClick(() => {
      if (this.active && !this.busy) {
        this.onTap();
      }
    })
  }
}

/** Filled (primary) or outlined button */
// 中文：胶囊按钮，高 42vp。filled 为主色实心按钮，否则为浅底色按钮；danger 使用错误色（删除等危险操作）。
@ComponentV2
export struct ActionButton {
  private store: Store = Store.get();
  // 按钮文字
  @Param text: string = '';
  // 实心（主操作）或浅色（次要操作）
  @Param filled: boolean = true;
  // 危险操作配色
  @Param danger: boolean = false;
  // 忙碌：文字前显示加载圈，点击被忽略（如“登录”请求进行中）
  @Param busy: boolean = false;
  // 是否撑满父容器宽度；否则按内容宽度
  @Param fullWidth: boolean = false;
  // 点击回调（busy 时不触发）
  @Event onTap: () => void = () => {
  };

  build() {
    Button({ type: ButtonType.Capsule, stateEffect: true }) {
      Row({ space: 6 }) {
        if (this.busy) {
          LoadingProgress()
            .width(18)
            .height(18)
            .color(this.filled ? this.store.palette().onPrimary : this.store.palette().accentUi)
        }
        Text(this.text)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.filled ? this.store.palette().onPrimary :
            (this.danger ? this.store.palette().bad : this.store.palette().accent))
      }
      .padding({ left: 18, right: 18 })
    }
    .height(42)
    .width(this.fullWidth ? '100%' : undefined)
    .backgroundColor(this.filled ? (this.danger ? this.store.palette().bad : this.store.palette().primary) :
      this.store.palette().chip)
    .onClick(() => {
      if (!this.busy) {
        this.onTap();
      }
    })
  }
}

// ------------------------------------------------------------------ chips & tags

// 中文：小标签（状态、分类等），文字色即传入颜色，背景为同色 12% 透明度
@ComponentV2
export struct Tag {
  @Param text: string = '';
  // 标签颜色，支持 #RRGGBB 或 #AARRGGBB
  @Param color: string = '#55606A';

  build() {
    // 9 位颜色（#AARRGGBB）先去掉原有透明度再交给 withAlpha，否则背景透明度会叠乘得不对
    Text(this.text)
      .fontSize(11)
      .fontColor(this.color)
      .backgroundColor(withAlpha(this.color.length === 9 ? '#' + this.color.substring(3) : this.color, 0.12))
      .borderRadius(6)
      .padding({ left: 6, right: 6, top: 2, bottom: 2 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .constraintSize({ maxWidth: 160 })
  }
}

/** Single-select chips row (filters, tabs inside a page) */
// 中文：横向可滚动的单选“药丸”筛选条（列表筛选、页内标签切换），选中项使用主题浅色背景
@ComponentV2
export struct ChipGroup {
  private store: Store = Store.get();
  // 选项文字
  @Param options: string[] = [];
  // 当前选中项下标
  @Param selected: number = 0;
  // 点击某项的回调（即使点的是已选中项也会回调），由父组件更新 selected
  @Event onSelect: (i: number) => void = (i: number) => {
  };

  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.options, (o: string, i: number) => {
          Text(o)
            .fontSize(13)
            .fontWeight(i === this.selected ? FontWeight.Medium : FontWeight.Normal)
            .fontColor(i === this.selected ? this.store.palette().accent : this.store.palette().subtle)
            .backgroundColor(i === this.selected ? this.store.palette().accentSoft : this.store.palette().chip)
            .borderRadius(16)
            .height(32)
            .padding({ left: 14, right: 14 })
            .onClick(() => {
              this.onSelect(i);
            })
        }, (o: string, i: number) => i + o)
      }
      .padding({ left: 16, right: 16 })
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
    .width('100%')
    .height(40)
  }
}

/**
 * Segmented single choice (settings). A component rather than a @Builder so that `selected`
 * is a tracked @Param and the highlight follows every tap.
 */
// 中文：分段单选控件（设置页的主题、语言、毛玻璃强度等）。选中段为主色背景，切换带 180ms 动画。
@ComponentV2
export struct Segmented {
  private store: Store = Store.get();
  // 各段文字，等分宽度
  @Param options: string[] = [];
  // 当前选中段
  @Param selected: number = 0;
  // 选择回调；点击已选中的段不会回调
  @Event onPick: (i: number) => void = (i: number) => {
  };

  build() {
    Row({ space: 4 }) {
      ForEach(this.options, (o: string, i: number) => {
        Text(o)
          .fontSize(13)
          .fontWeight(i === this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(i === this.selected ? this.store.palette().onPrimary : this.store.palette().text)
          .backgroundColor(i === this.selected ? this.store.palette().primary : Color.Transparent)
          .borderRadius(14)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .height(32)
          .layoutWeight(1)
          .accessibilityText(o + (i === this.selected ? t('，已选择') : ''))
          .animation({ duration: 180, curve: Curve.FastOutSlowIn })
          .onClick(() => {
            if (i !== this.selected) {
              this.onPick(i);
            }
          })
      }, (o: string, i: number) => i + ':' + o)
    }
    .padding(3)
    .backgroundColor(this.store.palette().chip)
    .borderRadius(17)
    .width('100%')
  }
}

// ------------------------------------------------------------------ states

/** Loading / empty / error placeholder, scrollable so pull-to-refresh still works */
// 中文：占位视图：加载中（转圈）/ 空（盒子图标）/ 错误（感叹号），可带说明文字和一个操作按钮。
// 外层用 Scroll 而不是 Column：放在 Refresh 里时空状态也能下拉刷新。
@ComponentV2
export struct StateView {
  private store: Store = Store.get();
  /** loading | empty | error */
  // 中文：状态类型：loading | empty | error
  @Param kind: string = 'loading';
  // 说明文字，可空
  @Param text: string = '';
  // 操作按钮文字（如“重试”），空串时不显示按钮
  @Param actionText: string = '';
  // 点击操作按钮的回调
  @Event onAction: () => void = () => {
  };

  build() {
    Scroll() {
      Column({ space: 12 }) {
        if (this.kind === 'loading') {
          LoadingProgress().width(40).height(40).color(this.store.palette().accentUi)
        } else {
          SymbolGlyph(this.kind === 'error' ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.archivebox'))
            .fontSize(44)
            .fontColor([this.kind === 'error' ? this.store.palette().bad : this.store.palette().subtle])
        }
        if (this.text.length > 0) {
          Text(this.text)
            .fontSize(14)
            .fontColor(this.store.palette().subtle)
            .textAlign(TextAlign.Center)
            .lineHeight(21)
            .padding({ left: 24, right: 24 })
        }
        if (this.actionText.length > 0) {
          ActionButton({
            text: this.actionText, filled: false, onTap: () => {
              this.onAction();
            }
          })
        }
      }
      .width('100%')
      .padding({ top: 80, bottom: 80 })
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
  }
}

// ------------------------------------------------------------------ inputs

// 中文：搜索框。提交（回车/搜索键）时回调去掉首尾空格的关键词；清空输入框时立即回调空串以恢复完整列表。
@ComponentV2
export struct SearchBox {
  private store: Store = Store.get();
  // 占位文字
  @Param placeholder: string = t('搜索');
  // 当前生效的关键词（父组件持有），用于判断“清空”是否需要重置筛选
  @Param value: string = '';
  // 搜索回调，参数为关键词（空串表示取消搜索）
  @Event onSearch: (v: string) => void = (v: string) => {
  };

  build() {
    Search({ value: this.value, placeholder: this.placeholder })
      .height(40)
      .backgroundColor(this.store.palette().chip)
      .placeholderColor(this.store.palette().tertiary)
      .fontColor(this.store.palette().text)
      .textFont({ size: 15 })
      .searchIcon({ color: this.store.palette().subtle })
      .cancelButton({ style: CancelButtonStyle.INPUT })
      .enterKeyType(EnterKeyType.Search)
      .onSubmit((v: string) => {
        this.onSearch(v.trim());
      })
      .onChange((v: string) => {
        // Clearing the box resets the filter right away
        if (v.length === 0 && this.value.length > 0) {
          this.onSearch('');
        }
      })
  }
}

/** Labeled input with hint and error */
// 中文：表单输入项：上方标签 + 输入框（单行 TextInput 或多行 TextArea）+ 下方错误/提示文字。
// 有错误时显示红色边框和错误文字，并隐藏提示文字（错误优先）。受控组件：值由父组件通过 value/onChange 管理。
@ComponentV2
export struct Field {
  private store: Store = Store.get();
  // 标签文字，空串不显示
  @Param label: string = '';
  // 输入框内容
  @Param value: string = '';
  // 占位提示
  @Param placeholder: string = '';
  // 辅助说明（灰色小字）
  @Param hint: string = '';
  // 错误文字，非空时边框变红
  @Param error: string = '';
  // 密码输入（仅单行模式有效）
  @Param password: boolean = false;
  // 多行模式（TextArea），用于命令、变量值、备注等
  @Param multiline: boolean = false;
  // 等宽字体，用于地址、密钥、cron 表达式、代码
  @Param mono: boolean = false;
  // 多行模式的最小显示行数（按 22vp 行高估算最小高度）
  @Param minLines: number = 3;
  // 数字键盘（单行模式）
  @Param numeric: boolean = false;
  // 单行输入框的组件 id（用于 focusControl.requestFocus），空串不设置
  @Param inputId: string = '';
  // 输入变化回调，父组件据此更新 value 并清除错误
  @Event onChange: (v: string) => void = (v: string) => {
  };

  build() {
    Column({ space: 6 }) {
      if (this.label.length > 0) {
        Text(this.label).fontSize(13).fontColor(this.store.palette().subtle).fontWeight(FontWeight.Medium)
      }
      if (this.multiline) {
        TextArea({ text: this.value, placeholder: this.placeholder })
          .fontSize(14)
          .fontFamily(this.mono ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(this.store.palette().text)
          .placeholderColor(this.store.palette().tertiary)
          .backgroundColor(this.store.palette().chip)
          .borderRadius(10)
          .constraintSize({ minHeight: this.minLines * 22 + 20 })
          .border({ width: this.error.length > 0 ? 1 : 0, color: this.store.palette().bad })
          .onChange((v: string) => {
            this.onChange(v);
          })
      } else {
        TextInput({ text: this.value, placeholder: this.placeholder })
          .type(this.password ? InputType.Password : (this.numeric ? InputType.Number : InputType.Normal))
          .fontSize(15)
          .fontFamily(this.mono ? 'monospace' : 'HarmonyOS Sans')
          .fontColor(this.store.palette().text)
          .placeholderColor(this.store.palette().tertiary)
          .backgroundColor(this.store.palette().chip)
          .borderRadius(10)
          .height(44)
          .id(this.inputId)
          .border({ width: this.error.length > 0 ? 1 : 0, color: this.store.palette().bad })
          .onChange((v: string) => {
            this.onChange(v);
          })
      }
      if (this.error.length > 0) {
        Text(this.error).fontSize(12).fontColor(this.store.palette().bad)
      } else if (this.hint.length > 0) {
        Text(this.hint).fontSize(12).fontColor(this.store.palette().subtle).lineHeight(18)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}

/** A switch row inside forms / settings */
// 中文：开关行：左侧标题 + 可选说明，右侧系统 Toggle，最小高度 52vp
@ComponentV2
export struct SwitchRow {
  private store: Store = Store.get();
  @Param title: string = '';
  // 说明文字，可空
  @Param desc: string = '';
  // 开关状态（受控）
  @Param on: boolean = false;
  // 切换回调
  @Event onToggle: (v: boolean) => void = (v: boolean) => {
  };

  build() {
    Row() {
      Column({ space: 2 }) {
        Text(this.title).fontSize(15).fontColor(this.store.palette().text)
        if (this.desc.length > 0) {
          Text(this.desc).fontSize(12).fontColor(this.store.palette().subtle).lineHeight(17)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(this.store.palette().accentUi)
        .onChange((v: boolean) => {
          this.onToggle(v);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ left: 16, right: 12, top: 6, bottom: 6 })
  }
}

/** Tappable settings row with optional trailing value and chevron */
// 中文：可点击的设置行：可选图标 + 标题 + 右侧当前值 + 右箭头，整行 52vp 均可点击
@ComponentV2
export struct NavRow {
  private store: Store = Store.get();
  // 左侧图标，undefined 时不显示
  @Param icon: Resource | undefined = undefined;
  @Param title: string = '';
  // 右侧显示的当前值（最宽 200vp，超出省略）
  @Param value: string = '';
  // 危险操作（如“删除服务器”“退出登录”）使用错误色
  @Param danger: boolean = false;
  // 是否显示右箭头
  @Param chevron: boolean = true;
  // 点击整行的回调
  @Event onTap: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(20)
          .fontColor([this.danger ? this.store.palette().bad : this.store.palette().accentUi])
      }
      Text(this.title)
        .fontSize(15)
        .fontColor(this.danger ? this.store.palette().bad : this.store.palette().text)
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      if (this.value.length > 0) {
        Text(this.value)
          .fontSize(13)
          .fontColor(this.store.palette().subtle)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 200 })
      }
      if (this.chevron) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([this.store.palette().subtle])
      }
    }
    .width('100%')
    .height(52)
    .padding({ left: 16, right: 12 })
    .onClick(() => {
      this.onTap();
    })
  }
}

/**
 * Rounded card section with an optional title above it.
 * `collapsible`: the title moves into the card as a tappable header showing `summary`, and the
 * content folds away (closed unless `open` is set).
 */
// 中文：圆角卡片分组（设置页、表单）。
// - 普通模式：卡片上方显示小标题，内容通过尾随闭包 content 传入；
// - 可折叠模式（collapsible）：标题变为卡片内可点击的头部，折叠时右侧显示 summary 摘要，展开/收起带动画。
// 毛玻璃：卡片底色为调色板中的半透明 card 色 + backdropBlur(vp2px(blurRadius()))，
// backdropBlur 的参数单位是 px，所以用 vp2px 转换；关闭毛玻璃时 blurRadius() 为 0，即不模糊。
@ComponentV2
export struct CardGroup {
  private store: Store = Store.get();
  // 分组标题
  @Param title: string = '';
  // 是否可折叠
  @Param collapsible: boolean = false;
  // 折叠时头部右侧显示的摘要（如当前选项）
  @Param summary: string = '';
  // 可折叠头部左侧的图标（主题色方块中的白色图标）
  @Param icon: Resource | undefined = undefined;
  // 初始是否展开（只在 aboutToAppear 读取一次）
  @Param open: boolean = false;
  // 当前展开状态，组件内部维护，之后不再跟随 open 变化
  @Local expanded: boolean = false;

  // 中文：用 open 初始化展开状态
  aboutToAppear(): void {
    this.expanded = this.open;
  }

  // 中文：默认空内容 Builder
  @Builder
  noContent() {
  }

  // 卡片内容（尾随闭包）
  @BuilderParam content: () => void = this.noContent;

  // 中文：可折叠模式的头部：图标 + 标题 + 摘要 + 旋转箭头；点击时在 animateTo 中切换 expanded，
  // 使箭头旋转与内容的透明度转场同步播放。展开时摘要置空，避免与下面的内容重复。
  @Builder
  header() {
    Row({ space: 12 }) {
      if (this.icon !== undefined) {
        Column() {
          SymbolGlyph(this.icon).fontSize(17).fontColor(['#FFFFFF'])
        }
        .width(30)
        .height(30)
        .borderRadius(9)
        .justifyContent(FlexAlign.Center)
        .backgroundColor(this.store.palette().accentUi)
      }
      Text(this.title)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.store.palette().text)
        .maxLines(1)
      Text(this.expanded ? '' : this.summary)
        .fontSize(13)
        .fontColor(this.store.palette().subtle)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .textAlign(TextAlign.End)
        .layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_down'))
        .fontSize(16)
        .fontColor([this.store.palette().subtle])
        .rotate({ angle: this.expanded ? 180 : 0 })
    }
    .width('100%')
    .height(56)
    .padding({ left: 16, right: 16 })
    .accessibilityText(this.title + '，' + (this.expanded ? t('已展开') : t('已折叠')))
    .onClick(() => {
      this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
        this.expanded = !this.expanded;
      });
    })
  }

  build() {
    Column() {
      if (this.title.length > 0 && !this.collapsible) {
        Text(this.title)
          .fontSize(13)
          .fontColor(this.store.palette().subtle)
          .fontWeight(FontWeight.Medium)
          .padding({ left: 16, bottom: 6 })
          .width('100%')
      }
      Column() {
        if (this.collapsible) {
          this.header()
          if (this.expanded) {
            Divider().color(this.store.palette().outline).strokeWidth(0.5).margin({ left: 16, right: 16 })
            Column() {
              this.content()
            }
            .width('100%')
            .transition(TransitionEffect.OPACITY)
          }
        } else {
          this.content()
        }
      }
      .width('100%')
      .backgroundColor(this.store.palette().card)
      .backdropBlur(this.store.blurPx())
      .borderRadius(16)
      .clip(true)
    }
    .width('100%')
  }
}

/** Big number tile on the dashboard */
// 中文：概览页的数字卡片：图标 + 标签、大号数值、可选副文字。高度撑满父容器，便于网格中等高排列；
// 同样使用半透明底色 + backdropBlur 的毛玻璃效果。
@ComponentV2
export struct StatTile {
  private store: Store = Store.get();
  // 标签（如“定时任务”）
  @Param label: string = '';
  // 大号数值文本
  @Param value: string = '';
  // 副文字（如“3 个运行中”），可空
  @Param sub: string = '';
  // 数值与图标颜色，空串用默认颜色
  @Param color: string = '';
  // 标签前的小图标，可空
  @Param icon: Resource | undefined = undefined;

  build() {
    Column({ space: 4 }) {
      Row({ space: 6 }) {
        if (this.icon !== undefined) {
          SymbolGlyph(this.icon)
            .fontSize(16)
            .fontColor([this.color.length > 0 ? this.color : this.store.palette().accentUi])
        }
        Text(this.label).fontSize(13).fontColor(this.store.palette().subtle).maxLines(1)
      }

      Text(this.value)
        .fontSize(26)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.color.length > 0 ? this.color : this.store.palette().text)
        .maxLines(1)
      if (this.sub.length > 0) {
        Text(this.sub).fontSize(12).fontColor(this.store.palette().subtle).maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding(14)
    .width('100%')
    .height('100%')
    .backgroundColor(this.store.palette().card)
    .backdropBlur(this.store.blurPx())
    .borderRadius(16)
  }
}
