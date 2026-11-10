import { image } from '@kit.ImageKit';
import { resolveDisplayImageUrl } from '../utils/DisplayMedia';
import { Avatar } from './Avatar';
import { resolveSettingsIcon } from '../utils/SettingsIcons';
import { Pressable } from './Pressable';
import { ColorTokens } from '../design/ColorTokens';
import { IconTokens } from '../design/IconTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { TypeTokens } from '../design/TypeTokens';
import { isImmersiveLightSenseSupported, GlassBlurStyle } from '../utils/immersiveMaterial';

/** 统计列 @Builder 的按引用参数（arkts-no-obj-literals 要求显式 interface） */
export interface PreviewStatSpec {
  value: number;
  label: string;
}

// 编辑页预览复用主页资料区的层级，媒体仅在页面保存成功后由宿主提交。
@Component
export struct EditableProfilePreview {
  @Prop avatar: string = '';
  // 像素图预览用 @Link（父子共享引用）而非 @Prop（单向拷贝）：
  // @Prop 对 image.PixelMap 这类复杂对象只按引用比较，选图后父组件更新不一定驱动本组件重渲染，
  // 导致「修改背景不即时显示、点保存才渲染」（保存后改走 URL 分支 + string 变化才触发）。
  @Link avatarPreview: image.PixelMap | null;
  @Link profileBackgroundPreview: image.PixelMap | null;
  @Prop nickname: string = '';
  @Prop bio: string = '';
  @Prop selectedGender: string = '0';
  @Prop profileId: number = 0;
  @Prop followingCount: number = 0;
  @Prop followerCount: number = 0;
  @Prop totalLikes: number = 0;
  @Prop profileBackground: string = '';
  @Prop backgroundStatus: string = '';
  @Prop uploadingBackground: boolean = false;
  /** 统计三列标签（默认有据原值；有径按旅行域传） */
  @Prop statLabels: string[] = ['关注', '粉丝', '获赞'];
  onPickBackground: () => void = (): void => {};
  onPickAvatar: () => void = (): void => {};

  private genderText(): string {
    return this.selectedGender === '1' ? '男' : (this.selectedGender === '2' ? '女' : '保密');
  }

  /**
   * 统计列 @Builder —— 参数必须是**对象字面量按引用传递**（官方 $$ 模式）。
   * 有据原版按值传参（previewStat(this.followingCount, '关注')）是静态快照：
   * 计数异步回填后 @Builder 不重执行，预览卡统计永远停在首帧 0（有径真机
   * 实测：日志行程计数=3 而卡显 0）。按引用传递后父级 @Prop 更新即驱动重渲染。
   */
  @Builder
  private previewStat($$: PreviewStatSpec): void {
    Column({ space: SpaceTokens.inlineTight }) {
      Text(String($$.value))
        .fontSize(TypeTokens.headline.size).fontFamily(TypeTokens.fontFamilySerif)
        .fontWeight(TypeTokens.headline.weight).fontColor(Color.White)
        .margin({ left: 5 })
      Text($$.label)
        .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily)
        .fontColor('#E6FFFFFF')
    }
    .width(LayoutTokens.profileStatWidth)
    .alignItems(HorizontalAlign.Start)
    .margin({ left: SpaceTokens.xs })
  }

  @Builder
  private profileContent(): void {
    Column() {
      Row({ space: SpaceTokens.sm }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(124).height(124).position({ x: -9, y: -7 })
            .radialGradient({
              center: [70, 74], radius: 74,
              colors: [['#5CFF84B4', 0.0], ['#28FF9BC3', 0.48], [ColorTokens.glassClear, 1.0]],
            })
            .borderRadius(RadiusTokens.pill).clip(true).hitTestBehavior(HitTestMode.None)
          if (this.avatarPreview) {
            Image(this.avatarPreview)
              .width(94).height(94).borderRadius(RadiusTokens.pill).objectFit(ImageFit.Cover).clip(true)
          } else {
            Avatar({ avatar: this.avatar, name: this.nickname, avatarSize: 94 })
          }
        }
        .width(124).height(110)

        Column({ space: SpaceTokens.inlineTight }) {
          Row({ space: SpaceTokens.inline }) {
            Text(this.nickname.length > 0 ? this.nickname : '你的昵称')
              .fontSize(TypeTokens.headline.size).fontFamily(TypeTokens.fontFamilySerif)
              .fontWeight(TypeTokens.headline.weight).fontColor(Color.White).maxLines(1)
            Text(this.genderText())
              .fontSize(TypeTokens.overline.size).fontFamily(TypeTokens.fontFamily)
              .fontWeight(TypeTokens.overline.weight)
              // 与 ProfileIdentity 的性别徽章同款配色（男=淡蓝底蓝字），改色需两处同步
              .fontColor(this.selectedGender === '1'
                ? ColorTokens.genderMaleText
                : this.selectedGender === '2' ? ColorTokens.genderFemaleText : ColorTokens.secondary)
              .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.inlineTight, bottom: SpaceTokens.inlineTight })
              .backgroundColor(this.selectedGender === '1'
                ? ColorTokens.genderMaleSurface
                : this.selectedGender === '2' ? ColorTokens.genderFemaleSurface : ColorTokens.sunken)
              .borderRadius(RadiusTokens.pill)
          }
          Text(this.bio.length > 0 ? this.bio : '在这里写下你的个人介绍')
            .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily)
            .fontColor('#E6FFFFFF').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text('ID: ' + (this.profileId > 0 ? String(this.profileId) : '-'))
            .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily).fontColor('#CCFFFFFF')
        }
        .layoutWeight(1).alignItems(HorizontalAlign.End)
      }
      .width('100%').height(110)
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.xs, bottom: SpaceTokens.xs })

      Row({ space: SpaceTokens.sm }) {
        this.previewStat({ value: this.followingCount, label: this.statLabels.length > 0 ? this.statLabels[0] : '关注' })
        this.previewStat({ value: this.followerCount, label: this.statLabels.length > 1 ? this.statLabels[1] : '粉丝' })
        this.previewStat({ value: this.totalLikes, label: this.statLabels.length > 2 ? this.statLabels[2] : '获赞' })
      }
      .width('100%').padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, bottom: SpaceTokens.sm })

      Row({ space: SpaceTokens.sm }) {
        Column() {
          this.editorAction('修改背景', (): void => { this.onPickBackground(); })
        }.layoutWeight(1)
        Column() {
          this.editorAction('修改头像', (): void => { this.onPickAvatar(); })
        }.layoutWeight(1)
      }
      .width('100%').padding({ bottom: SpaceTokens.xs })
    }
    .width('100%').height('100%').justifyContent(FlexAlign.End)
    .backgroundColor('#52000000')
  }

  @Builder
  private editorAction(label: string, action: () => void): void {
    Pressable({
      fillWidth: true,
      visualHeight: LayoutTokens.segmentedHeight,
      touchTargetHeight: LayoutTokens.minTouchTarget,
      action: action,
    }) {
      Row({ space: SpaceTokens.inlineTight }) {
        Image(resolveSettingsIcon('edit')).width(IconTokens.compact).height(IconTokens.compact).fillColor(ColorTokens.icon)
        Text(label)
          .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily)
          .fontWeight(TypeTokens.headline.weight).fontColor(ColorTokens.primary)
      }
      .width(160).height(LayoutTokens.segmentedHeight)
      .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
      .justifyContent(FlexAlign.Center).alignItems(VerticalAlign.Center)
      .backgroundColor(Color.Transparent)
      .border({ width: LayoutTokens.glassBorderWidth, color: ColorTokens.barBorder, style: BorderStyle.Solid })
      .borderRadius(RadiusTokens.lg)
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      if (this.profileBackgroundPreview) {
        Image(this.profileBackgroundPreview).width('100%').height('100%').objectFit(ImageFit.Cover)
      } else if (this.profileBackground) {
        Image(resolveDisplayImageUrl(this.profileBackground)).width('100%').height('100%').objectFit(ImageFit.Cover)
      } else {
        Column().width('100%').height('100%').backgroundColor(ColorTokens.sunken)
      }
      this.profileContent()
      if (this.backgroundStatus !== '') {
        Text(this.backgroundStatus)
          .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily)
          .fontColor(Color.White)
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.xs, bottom: SpaceTokens.xs })
          .backgroundColor(this.backgroundStatus === '待保存' ? '#A80A84FF' : '#A8000000')
          .borderRadius(RadiusTokens.pill)
          .position({ top: SpaceTokens.sm, left: SpaceTokens.sm })
      }
      if (this.uploadingBackground) {
        Column() {
          Row({ space: SpaceTokens.sm }) {
            LoadingProgress().width(IconTokens.compact).height(IconTokens.compact).color(ColorTokens.brand)
            Text('正在保存背景图')
              .fontSize(TypeTokens.caption.size).fontFamily(TypeTokens.fontFamily)
              .fontColor(Color.White)
          }
          .padding({ left: SpaceTokens.md, right: SpaceTokens.md, top: SpaceTokens.sm, bottom: SpaceTokens.sm })
          .backgroundBlurStyle(GlassBlurStyle.Card)
          .backgroundColor(isImmersiveLightSenseSupported() ? Color.Transparent : '#AA000000')
          .border({ width: LayoutTokens.glassBorderWidth, color: ColorTokens.glassWhite, style: BorderStyle.Solid })
          .borderRadius(RadiusTokens.floatingBar)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%').height('100%').justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .aspectRatio(16 / 10)
    .clip(true)
    .borderRadius(RadiusTokens.lg)
  }
}
