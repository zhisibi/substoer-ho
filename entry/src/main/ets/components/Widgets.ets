/**
 * Widgets.ets — the few building blocks of the native pages, styled after the Sub-Store web UI (NutUI cells on
 * rounded cards, the blue gradient primary button, small grey section titles) so the 服务管理 page feels like part
 * of the same app. Colors come from Store.palette() (Sub-Store's light / dark theme). Touch targets >= 40 vp.
 */
import { t } from '../common/I18n';
import { Store } from '../common/Store';
import { BarGlassMod, BarLook, GlassRimMod } from '../common/LightSense';

/** Header height without the status bar */
export const HEADER_H: number = 52;

/** Nav bar: back button, title (+ subtitle) and trailing actions, like the web UI's nav bar. */
@ComponentV2
export struct PageHeader {
  private store: Store = Store.get();
  @Param title: string = '';
  @Param subtitle: string = '';
  @Param showBack: boolean = false;
  /** Adds the status bar height on top (pages drawn edge to edge) */
  @Param topInset: boolean = true;
  @Event onBack: () => void = () => {
  };

  @Builder
  noActions() {
  }

  @BuilderParam actions: () => void = this.noActions;

  barLook(): BarLook {
    const l = new BarLook();
    l.on = this.store.navLight;
    l.dark = this.store.isDark();
    return l;
  }

  @Builder
  content() {
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
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.store.palette().text)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.subtitle.length > 0) {
          Text(this.subtitle)
            .fontSize(12)
            .fontColor(this.store.palette().tertiary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 1 })
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: this.showBack ? 0 : 8 })

      Row({ space: 2 }) {
        this.actions()
      }
    }
    .width('100%')
    .height(HEADER_H)
    .padding({ left: this.showBack ? 4 : 12, right: 8 })
    .alignItems(VerticalAlign.Center)
  }

  build() {
    Column() {
      Stack() {
        if (this.store.navLight) {
          // 沉浸光感 capsule: glass surface + two rim overlays, content on top (see LightSense.ets)
          Row()
            .width('100%')
            .height('100%')
            .borderRadius(HEADER_H / 2)
            .attributeModifier(new BarGlassMod(this.barLook()))
          Row()
            .width('100%')
            .height('100%')
            .borderRadius(HEADER_H / 2)
            .attributeModifier(new GlassRimMod(this.store.isDark(), 0))
            .hitTestBehavior(HitTestMode.None)
          Row()
            .width('100%')
            .height('100%')
            .borderRadius(HEADER_H / 2)
            .attributeModifier(new GlassRimMod(this.store.isDark(), 1))
            .hitTestBehavior(HitTestMode.None)
        }
        this.content()
      }
      .width('100%')
      .height(HEADER_H)
    }
    .width('100%')
    .height(HEADER_H + (this.topInset ? this.store.safeTop : 0))
    .padding({ left: 10, right: 10, top: this.topInset ? this.store.safeTop : 0 })
  }
}

/** Round icon button (44 vp hot zone). Do not .bindMenu() on it: the inner onClick swallows the tap. */
@ComponentV2
export struct IconBtn {
  private store: Store = Store.get();
  @Param icon: Resource = $r('sys.symbol.dot_grid_2x2');
  @Param label: string = '';
  @Param iconSize: number = 20;
  @Param color: string = '';
  @Param active: boolean = true;
  @Param busy: boolean = false;
  @Param box: number = 44;
  @Event onTap: () => void = () => {
  };

  build() {
    Stack() {
      if (this.busy) {
        LoadingProgress().width(22).height(22).color(this.store.palette().accentUi)
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

/** Primary (blue gradient, as the web UI) or secondary (tinted) capsule button. */
@ComponentV2
export struct ActionButton {
  private store: Store = Store.get();
  @Param text: string = '';
  @Param filled: boolean = true;
  @Param danger: boolean = false;
  @Param busy: boolean = false;
  @Param fullWidth: boolean = false;
  @Event onTap: () => void = () => {
  };

  bg0(): string {
    const p = this.store.palette();
    return this.filled ? (this.danger ? p.bad : p.primary) : (this.danger ? '#1AE56459' : p.accentSoft);
  }

  bg1(): string {
    return this.filled && !this.danger ? this.store.palette().primaryEnd : this.bg0();
  }

  build() {
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
        .maxLines(1)
        .fontColor(this.filled ? this.store.palette().onPrimary :
          (this.danger ? this.store.palette().bad : this.store.palette().accent))
    }
    .justifyContent(FlexAlign.Center)
    .padding({ left: 20, right: 20 })
    .height(42)
    .width(this.fullWidth ? '100%' : undefined)
    .borderRadius(21)
    .linearGradient({ angle: 90, colors: [[this.bg0(), 0], [this.bg1(), 1]] })
    .opacity(this.busy ? 0.7 : 1)
    .clickEffect({ level: ClickEffectLevel.LIGHT, scale: 0.97 })
    .accessibilityText(this.text)
    .onClick(() => {
      if (!this.busy) {
        this.onTap();
      }
    })
  }
}

/** Segmented single choice: the selected segment is a white (dark: lifted) pill on a grey track. */
@ComponentV2
export struct Segmented {
  private store: Store = Store.get();
  @Param options: string[] = [];
  @Param selected: number = 0;
  @Event onPick: (i: number) => void = (i: number) => {
  };

  build() {
    Row({ space: 4 }) {
      ForEach(this.options, (o: string, i: number) => {
        Text(o)
          .fontSize(13)
          .fontWeight(i === this.selected ? FontWeight.Medium : FontWeight.Normal)
          .fontColor(i === this.selected ? this.store.palette().accent : this.store.palette().subtle)
          .backgroundColor(i === this.selected ? this.store.palette().card : Color.Transparent)
          .borderRadius(8)
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
    .borderRadius(10)
    .width('100%')
  }
}

/** Cell with a switch on the right. */
@ComponentV2
export struct SwitchRow {
  private store: Store = Store.get();
  @Param title: string = '';
  @Param desc: string = '';
  @Param on: boolean = false;
  @Event onToggle: (v: boolean) => void = (v: boolean) => {
  };

  build() {
    Row() {
      Column({ space: 3 }) {
        Text(this.title).fontSize(15).fontColor(this.store.palette().text)
        if (this.desc.length > 0) {
          Text(this.desc).fontSize(12).fontColor(this.store.palette().tertiary).lineHeight(17)
        }
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: this.on })
        .selectedColor(this.store.palette().primary)
        .onChange((v: boolean) => {
          this.onToggle(v);
        })
    }
    .width('100%')
    .constraintSize({ minHeight: 52 })
    .padding({ left: 16, right: 12, top: 8, bottom: 8 })
  }
}

/** Cell: optional icon, title, trailing value and chevron. */
@ComponentV2
export struct NavRow {
  private store: Store = Store.get();
  @Param icon: Resource | undefined = undefined;
  @Param title: string = '';
  @Param value: string = '';
  @Param danger: boolean = false;
  @Param chevron: boolean = true;
  @Event onTap: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      if (this.icon !== undefined) {
        SymbolGlyph(this.icon)
          .fontSize(19)
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
          .fontSize(14)
          .fontColor(this.store.palette().tertiary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .constraintSize({ maxWidth: 210 })
      }
      if (this.chevron) {
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(15).fontColor([this.store.palette().tertiary])
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

/** Section: small grey title above a rounded card holding the content; optionally collapsible. */
@ComponentV2
export struct CardGroup {
  private store: Store = Store.get();
  @Param title: string = '';
  /** text under the card (grey, small) */
  @Param footer: string = '';
  /** tappable title row with a rotating chevron; content hidden while collapsed */
  @Param collapsible: boolean = false;
  /** current-value summary shown on the title row while collapsed */
  @Param summary: string = '';
  /** initial expanded state (collapsible only, read once in aboutToAppear) */
  @Param open: boolean = true;
  @Local expanded: boolean = true;

  aboutToAppear(): void {
    this.expanded = this.open;
  }

  @Builder
  noContent() {
  }

  @BuilderParam content: () => void = this.noContent;

  build() {
    Column() {
      if (this.title.length > 0) {
        Row({ space: 8 }) {
          Text(this.title)
            .fontSize(13)
            .fontColor(this.store.palette().tertiary)
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.collapsible && !this.expanded && this.summary.length > 0) {
            Text(this.summary)
              .fontSize(12)
              .fontColor(this.store.palette().tertiary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: 200 })
          }
          if (this.collapsible) {
            SymbolGlyph($r('sys.symbol.chevron_down'))
              .fontSize(14)
              .fontColor([this.store.palette().tertiary])
              .rotate({ angle: this.expanded ? 180 : 0 })
              .animation({ duration: 220, curve: Curve.FastOutSlowIn })
          }
        }
        .width('100%')
        .height(this.collapsible ? 40 : undefined)
        .padding({ left: 14, right: this.collapsible ? 10 : 0, bottom: this.collapsible ? 0 : 8 })
        .alignItems(VerticalAlign.Center)
        .accessibilityText(this.title)
        .onClick(() => {
          if (this.collapsible) {
            this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, () => {
              this.expanded = !this.expanded;
            });
          }
        })
      }
      if (!this.collapsible || this.expanded) {
        Column() {
          this.content()
        }
        .width('100%')
        .backgroundColor(this.store.palette().card)
        .borderRadius(12)
        .clip(true)
        .transition(TransitionEffect.OPACITY)
        if (this.footer.length > 0) {
          Text(this.footer)
            .fontSize(12)
            .lineHeight(18)
            .fontColor(this.store.palette().tertiary)
            .padding({ left: 14, right: 14, top: 8 })
            .width('100%')
        }
      }
    }
    .width('100%')
  }
}

/** Thin divider between cells of a card. */
@Builder
export function CellDivider() {
  Divider().color(Store.get().palette().divider).strokeWidth(0.5).margin({ left: 16 })
}
