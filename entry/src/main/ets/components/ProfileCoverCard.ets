/**
 * 资料封面卡 · 2026-11-10 对标有据 ProfileHeader + EditableProfilePreview。
 *
 * 有据的结构决策：**编辑页预览复用主页资料区的层级**（EditableProfilePreview
 * 文件头原文）——同一个 16:10 封面卡，主页只展示、编辑页加编辑动作。本组件
 * 两处共用：`editable=false`（我的页资料区）/ `true`（编辑资料页），保证
 * 「所见即所得」：编辑时改背景/头像/文案，看到的就是保存后的资料区。
 *
 * 与有据的差异都有落点：
 * · 统计三列按旅行域换值（行程/勋章/足迹），有据是 关注/粉丝/获赞——值由
 *   宿主页查询传入，组件不感知域；
 * · ID 行显示脱敏 UnionID（有径无数字用户 id）；
 * · 图源是 base64 data URI 或 URL（有径本轮本地存 base64，共享后端落地后
 *   换 URL），空源退符号占位/沉底面；
 * · 上传中的 LoadingProgress 遮罩不搬（有径无网络上传，保存是本地写盘）。
 *
 * 像素图预览用 @Link（父子共享引用）而非 @Prop（单向拷贝）：@Prop 对
 * image.PixelMap 这类复杂对象只按引用比较，选图后父组件更新不一定驱动
 * 本组件重渲染——「修改背景不即时显示、点保存才渲染」（有据踩过的坑原文）。
 */

import { image } from '@kit.ImageKit';
import { StatItem } from './StatRow';
import { Pressable } from './Pressable';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { IconSizes, LayoutTokens } from '../design/LayoutTokens';

const GENDER_MALE: number = 1;
const GENDER_FEMALE: number = 2;

@Component
export struct ProfileCoverCard {
  /** 编辑页 = true：画「修改背景/修改头像」动作行与「待保存」徽标 */
  @Prop editable: boolean = false;
  /** 恒白字系：封面图/深色沉底上渲染，不随主题翻档（有据同款 Color.White 字面量） */
  @Prop avatarSource: string = '';
  @Prop backgroundSource: string = '';
  @Prop nickname: string = '';
  @Prop bio: string = '';
  /** 0=未设 1=男 2=女 */
  @Prop gender: number = 0;
  @Prop uidLabel: string = '';
  @Prop stats: StatItem[] = [];
  /** 编辑页选图后的本地即时预览（未保存也先看到） */
  @Link avatarPreview: image.PixelMap | null;
  @Link backgroundPreview: image.PixelMap | null;
  /** 编辑页背景「待保存」徽标文案（空串不画） */
  @Prop backgroundStatus: string = '';
  /** 展示态（editable=false）图上右下的单动作胶囊文案（有据主页「编辑资料」同位） */
  @Prop actionLabel: string = '';
  onAction: () => void = (): void => {};
  onPickAvatar: () => void = (): void => {};
  onPickBackground: () => void = (): void => {};

  private genderText(): string {
    return this.gender === GENDER_MALE ? '男' : (this.gender === GENDER_FEMALE ? '女' : '保密');
  }

  @Builder
  private coverStat(item: StatItem) {
    Column({ space: SpaceTokens.xxs }) {
      Text(item.value)
        .fontSize(TypeTokens.headline.size)
        .fontWeight(TypeTokens.headline.weight)
        .fontFamily(TypeTokens.title.family)
        .fontColor(Color.White)
      Text(item.label)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor('#E6FFFFFF')
    }
    .width(LayoutTokens.profileStatWidth)
    .alignItems(HorizontalAlign.Start)
  }

  /** 封面图上的编辑动作：玻璃描边胶囊（有据 editorAction 同款配方） */
  @Builder
  private editorAction(label: string, symbol: Resource, action: () => void) {
    Pressable({
      visualHeight: LayoutTokens.segmentedHeight,
      action: action
    }) {
      Row({ space: SpaceTokens.xs }) {
        SymbolGlyph(symbol)
          .fontSize(IconSizes.control)
          .fontColor([ColorTokens.primary])
        Text(label)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(TypeTokens.headline.weight)
          .fontColor(ColorTokens.primary)
      }
      .height(LayoutTokens.segmentedHeight)
      .padding({ left: SpaceTokens.md, right: SpaceTokens.md })
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .border({
        width: LayoutTokens.glassBorderWidth,
        color: ColorTokens.glassBarBorder,
        style: BorderStyle.Solid
      })
      .borderRadius(RadiusTokens.pill)
      .backgroundColor('#66000000')
    }
  }

  /** 图源三态：像素预览 > 图源串 > 缺省面。头像空源退符号占位（ProfileStore 单点） */
  @Builder
  private avatarView() {
    if (this.avatarPreview !== null) {
      Image(this.avatarPreview)
        .width(LayoutTokens.profileAvatarSize)
        .height(LayoutTokens.profileAvatarSize)
        .borderRadius(RadiusTokens.pill)
        .objectFit(ImageFit.Cover)
    } else if (this.avatarSource.length > 0) {
      Image(this.avatarSource)
        .width(LayoutTokens.profileAvatarSize)
        .height(LayoutTokens.profileAvatarSize)
        .borderRadius(RadiusTokens.pill)
        .objectFit(ImageFit.Cover)
        .draggable(false)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Circle()
          .width(LayoutTokens.profileAvatarSize)
          .height(LayoutTokens.profileAvatarSize)
          .fill(ColorTokens.primaryTint)
        SymbolGlyph($r('sys.symbol.person_crop_circle_fill_1'))
          .fontSize(LayoutTokens.profileAvatarSize * 0.62)
          .fontColor([ColorTokens.primary])
      }
      .width(LayoutTokens.profileAvatarSize)
      .height(LayoutTokens.profileAvatarSize)
    }
  }

  build() {
    Stack({ alignContent: Alignment.BottomStart }) {
      // 背景三态
      if (this.backgroundPreview !== null) {
        Image(this.backgroundPreview)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
      } else if (this.backgroundSource.length > 0) {
        Image(this.backgroundSource)
          .width('100%')
          .height('100%')
          .objectFit(ImageFit.Cover)
          .draggable(false)
      } else {
        // 无图缺省面**恒深**（#1C1C1E，iOS 系深灰）：这层恒白字系——浅色档 sunken
        // #E9E9EC 上白字对比 1.6:1 不可读（有据同款结构被用户背景图掩盖的问题），
        // 恒深面让「没设置背景图」与「设了深色图」的白字同读。
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#1C1C1E')
      }

      // 内容层：身份行 + 统计行（+ 编辑动作行）
      Column() {
        Row({ space: SpaceTokens.sm }) {
          this.avatarView()

          Column({ space: SpaceTokens.xxs }) {
            Row({ space: SpaceTokens.xs }) {
              Text(this.nickname.length > 0 ? this.nickname : '你的昵称')
                .fontSize(TypeTokens.headline.size)
                .fontWeight(TypeTokens.headline.weight)
                .fontFamily(TypeTokens.title.family)
                .fontColor(Color.White)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              // 性别徽章：有据 ProfileIdentity 同款配色（男=淡蓝底蓝字，女=淡粉底粉字）
              Text(this.genderText())
                .fontSize(TypeTokens.overline.size)
                .fontWeight(TypeTokens.overline.weight)
                .fontColor(this.gender === GENDER_MALE
                  ? ColorTokens.genderMaleText
                  : this.gender === GENDER_FEMALE ? ColorTokens.genderFemaleText : '#E6FFFFFF')
                .padding({
                  left: SpaceTokens.sm, right: SpaceTokens.sm,
                  top: SpaceTokens.xxs, bottom: SpaceTokens.xxs
                })
                .backgroundColor(this.gender === GENDER_MALE
                  ? ColorTokens.genderMaleSurface
                  : this.gender === GENDER_FEMALE ? ColorTokens.genderFemaleSurface : '#4D000000')
                .borderRadius(RadiusTokens.pill)
            }
            .alignItems(VerticalAlign.Center)

            Text(this.bio.length > 0 ? this.bio : '在这里写下你的个人介绍')
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor('#E6FFFFFF')
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('ID: ' + (this.uidLabel.length > 0 ? this.uidLabel : '-'))
              .fontSize(TypeTokens.caption.size)
              .fontWeight(450)
              .fontColor('#99FFFFFF')
          }
          // 身份块右对齐（有据 EditableProfilePreview:100 同款：头像在左，信息靠右收齐）
          .alignItems(HorizontalAlign.End)
          .layoutWeight(1)
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        // 统计三列（旅行域：行程/勋章/足迹；有据是 关注/粉丝/获赞）
        Row({ space: SpaceTokens.sm }) {
          ForEach(this.stats, (item: StatItem) => {
            this.coverStat(item)
          }, (item: StatItem): string => `${item.key}:${item.value}`)
        }
        .width('100%')
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, top: SpaceTokens.sm, bottom: SpaceTokens.sm })

        if (!this.editable && this.actionLabel.length > 0) {
          Row() {
            Column() {
              this.editorAction(this.actionLabel, $r('sys.symbol.person_crop_circle_fill'), (): void => {
                this.onAction();
              })
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .justifyContent(FlexAlign.End)
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, bottom: SpaceTokens.sm })
        }
        if (this.editable) {
          Row({ space: SpaceTokens.sm }) {
            Column() {
              this.editorAction('修改背景', $r('sys.symbol.picture_fill'), (): void => {
                this.onPickBackground();
              })
            }
            .layoutWeight(1)
            Column() {
              this.editorAction('修改头像', $r('sys.symbol.person_crop_circle_fill'), (): void => {
                this.onPickAvatar();
              })
            }
            .layoutWeight(1)
          }
          .width('100%')
          .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, bottom: SpaceTokens.sm })
        }
      }
      .width('100%')
      .padding({ top: SpaceTokens.base, bottom: this.editable ? SpaceTokens.xxs : SpaceTokens.sm })

      // 背景「待保存」徽标（编辑页选图未保存时）
      if (this.backgroundStatus.length > 0) {
        Text(this.backgroundStatus)
          .fontSize(TypeTokens.caption.size)
          .fontWeight(450)
          .fontColor(Color.White)
          .padding({
            left: SpaceTokens.sm, right: SpaceTokens.sm,
            top: SpaceTokens.xxs, bottom: SpaceTokens.xxs
          })
          .backgroundColor('#A80A84FF')
          .borderRadius(RadiusTokens.pill)
          .position({ top: SpaceTokens.sm, left: SpaceTokens.sm })
      }
    }
    .width('100%')
    .aspectRatio(16 / 10)
    .clip(true)
    .borderRadius(RadiusTokens.card)
  }
}
