/**
 * 文件说明：通用单行文本输入对话框。
 *
 * 主要内容：PromptArgs（参数）、InputDialogBody（对话框内容组件）、promptText()（对外的 Promise 接口）。
 * 实现方式：UIContext.getPromptAction().openCustomDialog + ComponentContent，
 *   不需要在页面里声明 CustomDialogController，任何 V2 组件或普通函数里都能直接 await。
 * 使用位置：views/FilesView.ets（新建文件/文件夹、重命名）、views/DepsView.ets（输入依赖名）等。
 */
import { t } from '../common/I18n';
import { ComponentContent } from '@kit.ArkUI';
import { Store } from '../common/Store';
import { Log } from '../common/Log';

/** Parameters of a text prompt */
// 中文：对话框参数。通过 ComponentContent 传入 inputDialogBuilder，再交给 InputDialogBody。
export class PromptArgs {
  // 标题、说明文字（可空）、占位提示和初始值
  title: string = '';
  message: string = '';
  placeholder: string = '';
  initial: string = '';
  okText: string = t('确定');
  // numeric：数字键盘；password：密码输入（优先级高于 numeric）。promptText 目前只暴露 numeric
  numeric: boolean = false;
  password: boolean = false;
  /** Called once with the text, or null when cancelled */
  // 中文：结果回调，由 promptText 替换为 finish()，内部保证只生效一次
  done: (v: string | null) => void = (v: string | null) => {
  };
}

/** Body of the prompt dialog */
// 中文：对话框内容组件：标题 + 说明 + 输入框 + 取消/确定按钮，宽 340vp 卡片样式。
@ComponentV2
struct InputDialogBody {
  // 全局 Store：调色板
  private store: Store = Store.get();
  // 对话框参数（只读）
  @Param args: PromptArgs = new PromptArgs();
  // 当前输入内容，组件内部状态
  @Local text: string = '';

  // 中文：首次出现时用初始值填充输入框
  aboutToAppear(): void {
    this.text = this.args.initial;
  }

  build() {
    Column({ space: 14 }) {
      Text(this.args.title)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.store.palette().text)
        .width('100%')
      if (this.args.message.length > 0) {
        Text(this.args.message)
          .fontSize(14)
          .lineHeight(20)
          .fontColor(this.store.palette().subtle)
          .width('100%')
      }
      // defaultFocus(true) 让对话框弹出即聚焦并拉起键盘；键盘上的“回车/完成”等同点击确定
      TextInput({ text: this.text, placeholder: this.args.placeholder })
        .type(this.args.password ? InputType.Password : (this.args.numeric ? InputType.Number : InputType.Normal))
        .fontSize(16)
        .fontColor(this.store.palette().text)
        .placeholderColor(this.store.palette().tertiary)
        .backgroundColor(this.store.palette().chip)
        .borderRadius(10)
        .height(46)
        .defaultFocus(true)
        .onChange((v: string) => {
          this.text = v;
        })
        .onSubmit(() => {
          this.args.done(this.text);
        })
      // 底部按钮：取消回传 null，确定回传当前文本（是否 trim 由调用方决定）
      Row({ space: 12 }) {
        Button(t('取消'), { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(42)
          .fontColor(this.store.palette().accent)
          .backgroundColor(this.store.palette().chip)
          .onClick(() => {
            this.args.done(null);
          })
        Button(this.args.okText, { type: ButtonType.Capsule })
          .layoutWeight(1)
          .height(42)
          .fontColor(this.store.palette().onPrimary)
          .backgroundColor(this.store.palette().primary)
          .onClick(() => {
            this.args.done(this.text);
          })
      }
      .width('100%')
    }
    .padding(22)
    .width(340)
    .backgroundColor(this.store.isDark() ? '#1A2127' : '#FFFFFF')
    .borderRadius(24)
  }
}

// 中文：全局 @Builder，供 wrapBuilder 包装后交给 ComponentContent（ComponentContent 只接受全局 Builder）。
@Builder
function inputDialogBuilder(args: PromptArgs) {
  InputDialogBody({ args: args })
}

/**
 * Shows a text prompt and resolves with the entered text, or null when cancelled / dismissed.
 * Uses PromptAction.openCustomDialog so it works from any V2 component without a dialog controller.
 */
// 中文：弹出文本输入框。
// - 参数：title 标题；placeholder 占位提示；initial 初始文本；message 可选说明；numeric 可选，是否数字键盘。
// - 返回：Promise，确定时得到输入文本，取消 / 点遮罩 / 返回键得到 null。
// - 注意：Store.uiCtx 尚未就绪（Ability 还没创建窗口）时直接返回 null，不会抛错。
export function promptText(title: string, placeholder: string, initial: string, message?: string,
  numeric?: boolean, password?: boolean): Promise<string | null> {
  return new Promise<string | null>((resolve: (v: string | null) => void) => {
    const store = Store.get();
    const ui = store.uiCtx;
    if (ui === null) {
      resolve(null);
      return;
    }
    const args = new PromptArgs();
    args.title = title;
    args.placeholder = placeholder;
    args.initial = initial;
    args.message = message !== undefined ? message : '';
    args.numeric = numeric === true;
    args.password = password === true;
    // 为什么需要 settled：按钮回调与 onWillDismiss 都可能触发，Promise 只能 resolve 一次，同时避免重复关闭
    let settled = false;
    const content = new ComponentContent<PromptArgs>(ui, wrapBuilder(inputDialogBuilder), args);
    const finish = (v: string | null) => {
      if (settled) {
        return;
      }
      settled = true;
      ui.getPromptAction().closeCustomDialog(content).catch(() => {
        Log.w('Dialog', 'close failed');
      });
      resolve(v);
    };
    // 把结束函数交给内容组件，按钮点击时调用
    args.done = finish;
    ui.getPromptAction().openCustomDialog(content, {
      alignment: DialogAlignment.Center,
      autoCancel: true,
      // 返回键 / 点击遮罩：设置了 onWillDismiss 后系统不会自动关闭，必须手动 action.dismiss()，并按“取消”处理
      onWillDismiss: (action: DismissDialogAction) => {
        action.dismiss();
        if (!settled) {
          settled = true;
          resolve(null);
        }
      }
    }).catch((e: Error) => {
      Log.e('Dialog', 'open failed', e);
      resolve(null);
    });
  });
}
