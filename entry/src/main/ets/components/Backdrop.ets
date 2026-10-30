/**
 * AppBackdrop: the selected 背景 gradient drawn behind a page (纯色 renders nothing; the page's own
 * palette bg shows). Put it as the first child of a page's root Stack — the palette turns cards
 * translucent while a backdrop is selected, so the gradient shows through them.
 */
import { Store } from '../common/Store';

@ComponentV2
export struct AppBackdrop {
  private store: Store = Store.get();

  build() {
    if (this.store.backdropOn()) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 160,
          colors: [[this.store.backdropStops()[0], 0], [this.store.backdropStops()[1], 0.55],
            [this.store.backdropStops()[2], 1]]
        })
    }
  }
}
