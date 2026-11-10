import { ProfileIdentity } from './ProfileIdentity';
import { ProfileStatItem } from './ProfileStatItem';
import { GlassPillButton } from '../design/GlassPillButton';
import { ColorTokens } from '../design/ColorTokens';
import { SpaceTokens } from '../design/SpaceTokens';

// 个人资料区只负责呈现与操作意图；页面决定跳转、分享和数据加载等领域行为。
// 三颗按钮（编辑资料 / 草稿箱 / 废纸篓）统一走 GlassPillButton 模板（useSystemMaterial=false：
// 本组件宿主在内容区，材质渲染不出图，玻璃兜底配方收在模板内部，见基准 §7.6.26）。
@Component
export struct ProfileHeader {
  @Prop avatar: string = '';
  @Prop name: string = '';
  @Prop gender: number = 0;
  @Prop bio: string = '';
  @Prop userId: number = 0;
  @Prop isLoggedIn: boolean = false;
  @Prop followingCount: number = 0;
  @Prop followerCount: number = 0;
  @Prop totalLikes: number = 0;
  /** 统计三列标签（默认有据原值 关注/粉丝/获赞；有径按旅行域传 行程/勋章/足迹） */
  @Prop statLabels: string[] = ['关注', '粉丝', '获赞'];
  /** 草稿箱/废纸篓胶囊排（有据 UGC 域；有径无对应页传 false 不渲染） */
  @Prop showToolPills: boolean = true;
  @Prop onBackground: boolean = false;
  onOpenFollowing: () => void = (): void => {};
  onOpenFollowers: () => void = (): void => {};
  onEdit: () => void = (): void => {};
  onOpenDrafts: () => void = (): void => {};
  onOpenTrash: () => void = (): void => {};
  onLogin: () => void = (): void => {};


  build() {
    Column() {
      ProfileIdentity({
        avatar: this.avatar,
        name: this.name,
        gender: this.gender,
        bio: this.bio,
        userId: this.userId,
        onBackground: this.onBackground,
      })
      // 统计三列独占一行。有据原版把编辑资料胶囊与三列并排（Blank 弹开），
      // 363vp 屏实测放不下：三列 240 + 间隔 36 + 胶囊 76 + 行 padding 24 = 376vp，
      // 胶囊右缘顶满屏宽被裁（有径真机 dump 实证）。胶囊拆到独立一行右对齐——
      // 独立胶囊行的排版语言与有据草稿箱/废纸篓行一致。
      Row({ space: SpaceTokens.sm }) {
        ProfileStatItem({
          value: this.followingCount,
          label: this.statLabels.length > 0 ? this.statLabels[0] : '关注',
          onBackground: this.onBackground,
          clickable: true,
          onOpen: (): void => { this.onOpenFollowing(); },
        })
        ProfileStatItem({
          value: this.followerCount,
          label: this.statLabels.length > 1 ? this.statLabels[1] : '粉丝',
          onBackground: this.onBackground,
          clickable: true,
          onOpen: (): void => { this.onOpenFollowers(); },
        })
        ProfileStatItem({ value: this.totalLikes, label: this.statLabels.length > 2 ? this.statLabels[2] : '获赞', onBackground: this.onBackground })
      }
      .width('100%')
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm })

      Row() {
        GlassPillButton({
          label: this.isLoggedIn ? '编辑资料' : '去登录',
          highlight: !this.isLoggedIn,
          action: (): void => { this.isLoggedIn ? this.onEdit() : this.onLogin(); },
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, bottom: SpaceTokens.sm })

      if (this.isLoggedIn && this.showToolPills) {
        Row({ space: SpaceTokens.sm }) {
          Column() {
            GlassPillButton({
              label: '草稿箱',
              icon: 'draftBox',
              fillWidth: true,
              action: (): void => { this.onOpenDrafts(); },
            })
          }
          .layoutWeight(1)
          Column() {
            GlassPillButton({
              label: '废纸篓',
              icon: 'trash',
              fillWidth: true,
              action: (): void => { this.onOpenTrash(); },
            })
          }
          .layoutWeight(1)
        }
        .width('100%')
        .padding({ left: SpaceTokens.sm, right: SpaceTokens.sm, bottom: SpaceTokens.xs })
      }
    }
    .width('100%')
  }
}
