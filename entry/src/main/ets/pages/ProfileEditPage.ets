/**
 * 编辑资料页 · 「我的」页资料区「编辑资料」胶囊进入（2026-11-10 全量对标有据
 * EditProfilePage，用户指令「编辑页也要全量搬」）。
 *
 * 【与「有据」共享资料的口径】本页读写的字段集与有据 `User` 完全同形：
 * 昵称 / 性别（0=未设 1=男 2=女）/ 简介 / 头像 / 资料封面背景。有据编辑页的
 * 表单交互（性别三段、20 字昵称、100 字简介计数）、脏态返回拦截
 * （「放弃未保存的修改？」）、昵称必填校验（1-20 字）逐项对齐。
 *
 * 与有据的实质差异只有一条落点：**图片上传不搬**。有据是选图 → compressAvatar →
 * COS 直传 → URL 回写；有径本轮无后端，选图 → compressAvatar → bytes 转
 * base64 data URI → ProfileStore 本地落盘。共享后端落地时只换
 * saveProfile 的落点（base64 → 服务端 URL 上传），选图/压缩/预览链路原样复用。
 *
 * 编辑面即预览面：顶部 EditableProfilePreview 为有据同名组件原样搬运，
 * 与我的页资料区（ProfileHeader 全套）同一层级，改背景/头像/文案即时可见。
 */

import { SegmentButton, SegmentButtonOptions, SegmentButtonTextItem, ItemRestriction } from '@kit.ArkUI';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { common } from '@kit.AbilityKit';
import { TripDao, TripSummary } from '../data/TripDao';
import { BadgeDao } from '../data/BadgeDao';
import { BadgeRecord } from '../utils/BadgeBoard';
import { ProfileStore, UserProfileData } from '../data/ProfileStore';
import { AccountStore } from '../data/AccountStore';
import { PROFILE_NAV } from '../common/constants/AppNav';
import { compressAvatar, CompressedImage, toDataUri } from '../utils/ImageCompress';
import { EditableProfilePreview } from '../components/EditableProfilePreview';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { RadiusTokens } from '../design/RadiusTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { LayoutTokens } from '../design/LayoutTokens';
import { HdsChrome } from '../design/HdsChrome';
import { HdsNavDestination, HdsNavDestinationTitleMode } from '@kit.UIDesignKit';
import { Logger } from '../common/logger/Logger';

/** 性别三段与存值的映射：显示序 ↔ 有据 User.gender 语义（0 未设/1 男/2 女） */
const GENDER_MALE: number = 1;
const GENDER_FEMALE: number = 2;
const GENDER_UNSET: number = 0;
/** 有据同款限长（昵称必填 1-20） */
const NICKNAME_MAX: number = 20;
const BIO_MAX: number = 100;

@Component
export struct ProfileEditPage {
  // 深浅档代 tick：与 SettingsPage 同款（HdsChrome.themeTick 机制）
  @StorageProp('chromeThemeTick') chromeThemeTick: number = 0;

  @State private nickname: string = '';
  @State private bio: string = '';
  @State private genderIndexes: number[] = [2];
  // SegmentButton 用 $ 双向绑定 selectedIndexes：组件点击直接写回本数组
  // selectedBackgroundColor 必须显式给：官方 tab 档选中面在深色实测 #E5E5E5 不随主题翻，
  // 选中文字却翻白 → 白字压白珠（有据编辑资料页真机实拍，glass_selection_surface 同源同值）
  @State private genderOptions: SegmentButtonOptions = SegmentButtonOptions.tab({
    buttons: [
      { text: '男' },
      { text: '女' },
      { text: '保密' }
    ] as ItemRestriction<SegmentButtonTextItem>,
    selectedBackgroundColor: $r('app.color.glass_selection_surface')
  });
  @State private avatar: string = '';
  @State private profileBackground: string = '';
  @State private avatarPreview: image.PixelMap | null = null;
  @State private backgroundPreview: image.PixelMap | null = null;
  @State private backgroundStatus: string = '';
  @State private avatarPending: boolean = false;
  @State private backgroundPending: boolean = false;
  @State private saving: boolean = false;
  @State private barScrolled: boolean = false;
  @State private tripCount: number = 0;
  @State private badgeCount: number = 0;
  @State private cityCount: number = 0;
  private barScroller: Scroller = new Scroller();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  /** 脏态基线（有据 captureTextBaseline 同款） */
  private originalNickname: string = '';
  private originalBio: string = '';
  private originalGender: number = 0;
  private pendingAvatarImage: CompressedImage | null = null;
  private pendingBackgroundImage: CompressedImage | null = null;

  aboutToAppear(): void {
    this.loadAndFill();
  }

  private loadAndFill(): void {
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    ProfileStore.loadProfile(ctx, AccountStore.uid()).then((p: UserProfileData): void => {
      this.nickname = p.nickname;
      this.bio = p.bio;
      this.avatar = p.avatar;
      this.profileBackground = p.profileBackground;
      this.genderIndexes = [p.gender === GENDER_MALE ? 0 : (p.gender === GENDER_FEMALE ? 1 : 2)];
      this.captureTextBaseline();
    }).catch((err: Error): void => {
      Logger.warn('Ui.ProfileEdit', `资料回填失败: ${err.message}`);
    });
    // 预览卡统计行（与我的页统计同源三查询，只取个数——BadgeRecord 城市去重即足迹）
    TripDao.listSummaries(ctx).then((rows: TripSummary[]): void => {
      this.tripCount = rows.length;
    }).catch((err: Error): void => {
      Logger.warn('Ui.ProfileEdit', `行程计数读取失败: ${err.message}`);
    });
    BadgeDao.listMine(ctx).then((rows: BadgeRecord[]): void => {
      this.badgeCount = rows.length;
      const cities: Set<string> = new Set<string>();
      rows.forEach((r: BadgeRecord): void => {
        if (r.city.length > 0) {
          cities.add(r.city);
        }
      });
      this.cityCount = cities.size;
    }).catch((err: Error): void => {
      Logger.warn('Ui.ProfileEdit', `勋章计数读取失败: ${err.message}`);
    });
  }

  private captureTextBaseline(): void {
    this.originalNickname = this.nickname;
    this.originalBio = this.bio;
    this.originalGender = this.currentGender();
  }

  private currentGender(): number {
    const idx: number = this.genderIndexes.length > 0 ? this.genderIndexes[0] : 2;
    return idx === 0 ? GENDER_MALE : (idx === 1 ? GENDER_FEMALE : GENDER_UNSET);
  }

  /** 有据 hasUnsavedChanges 同款：文本三态 + 待保存图（本地 PixelMap 预览也算未保存） */
  private hasUnsavedChanges(): boolean {
    return this.nickname !== this.originalNickname || this.bio !== this.originalBio ||
      this.currentGender() !== this.originalGender || this.avatarPending || this.backgroundPending;
  }

  private onBack(): void {
    if (!this.hasUnsavedChanges()) {
      PROFILE_NAV.pop();
      return;
    }
    this.getUIContext().showAlertDialog({
      title: '放弃未保存的修改？',
      message: '资料和待保存的头像、背景图都不会保留。',
      primaryButton: { value: '继续编辑', action: (): void => {} },
      secondaryButton: {
        value: '放弃修改',
        fontColor: ColorTokens.danger,
        action: (): void => {
          PROFILE_NAV.pop();
        }
      }
    });
  }

  /**
   * 选图 → 压缩 → 暂存。有据 onPickAvatar 同款流程（PhotoViewPicker 免权限安全控件）；
   * 区别只在末端：暂存 bytes 转 base64 的动作挪到保存时统一做（与有据「保存时统一
   * 上传」同构），选图只更新本地预览。
   */
  private async pickImage(isAvatar: boolean): Promise<void> {
    if (this.saving) {
      return;
    }
    let uris: string[] = [];
    try {
      const ph = new photoAccessHelper.PhotoViewPicker();
      const res = await ph.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });
      uris = res.photoUris ?? [];
    } catch (e) {
      return;
    }
    if (uris.length === 0) {
      return;
    }
    try {
      // 头像 512px、背景 1440px（有据 compressAvatar 同款两档限长）
      const compressed: CompressedImage = await compressAvatar(uris[0], isAvatar ? 512 : 1440);
      if (isAvatar) {
        this.pendingAvatarImage = compressed;
        this.avatarPreview = compressed.preview;
        this.avatarPending = true;
      } else {
        this.pendingBackgroundImage = compressed;
        this.backgroundPreview = compressed.preview;
        this.backgroundPending = true;
        this.backgroundStatus = '待保存';
      }
    } catch (e) {
      this.getUIContext().getPromptAction().showToast({ message: '图片处理失败：' + (e as Error).message });
    }
  }

  /** 有据 valid() 同款：昵称必填 1-20 字、简介 ≤100 字 */
  private valid(): boolean {
    const n: string = this.nickname.trim();
    if (n.length < 1 || n.length > NICKNAME_MAX) {
      return false;
    }
    if (this.bio.length > BIO_MAX) {
      return false;
    }
    return true;
  }

  private onSave(): void {
    if (this.saving) {
      return;
    }
    if (!this.valid()) {
      this.getUIContext().getPromptAction().showToast({ message: '昵称 1-20 字、简介不超过 100 字' });
      return;
    }
    this.saving = true;
    const ctx: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
    // 本地落盘链路：待保存图 → base64 data URI（有据此处是 COS 上传，共享后端落地时对调）
    let nextAvatar: string = this.avatar;
    let nextBackground: string = this.profileBackground;
    try {
      if (this.pendingAvatarImage !== null) {
        nextAvatar = toDataUri(this.pendingAvatarImage.bytes);
      }
      if (this.pendingBackgroundImage !== null) {
        nextBackground = toDataUri(this.pendingBackgroundImage.bytes);
      }
    } catch (e) {
      this.saving = false;
      this.getUIContext().getPromptAction().showToast({ message: '图片编码失败，请重试' });
      return;
    }
    const data: UserProfileData = {
      nickname: this.nickname.trim(),
      bio: this.bio.trim(),
      gender: this.currentGender(),
      avatar: nextAvatar,
      profileBackground: nextBackground
    };
    ProfileStore.saveProfile(ctx, AccountStore.uid(), data).then((): void => {
      // 与有据同款：清 pending、重锁基线、可见确认后返回
      this.avatar = nextAvatar;
      this.profileBackground = nextBackground;
      this.avatarPreview = null;
      this.backgroundPreview = null;
      this.pendingAvatarImage = null;
      this.pendingBackgroundImage = null;
      this.avatarPending = false;
      this.backgroundPending = false;
      this.backgroundStatus = '';
      this.captureTextBaseline();
      this.getUIContext().getPromptAction().showToast({ message: '已保存' });
      setTimeout((): void => {
        PROFILE_NAV.pop();
      }, 350);
    }).catch((err: Error): void => {
      Logger.warn('Ui.ProfileEdit', `资料保存失败: ${err.message}`);
      this.backgroundStatus = this.backgroundPending ? '保存失败' : this.backgroundStatus;
      this.getUIContext().getPromptAction().showToast({ message: '保存失败：' + err.message });
    }).finally((): void => {
      this.saving = false;
    });
  }

  /** 绝对滚动偏移 → 顶栏磨砂开关（>0 即开，静止归零），SettingsPage 同款 */
  private syncBarScroll(): void {
    const y: number = this.barScroller.currentOffset().yOffset;
    const on: boolean = y > 0;
    if (on !== this.barScrolled) {
      this.barScrolled = on;
    }
  }

  @Builder
  private fieldLabel(title: string, counter: string, counterHot: boolean) {
    Row() {
      Text(title)
        .fontSize(TypeTokens.small.size)
        .fontWeight(600)
        .fontColor(ColorTokens.muted)
      Blank()
      Text(counter)
        .fontSize(TypeTokens.caption.size)
        .fontWeight(450)
        .fontColor(counterHot ? ColorTokens.primary : ColorTokens.muted)
    }
    .width('100%')
  }

  build() {
    HdsNavDestination() {
      List({ space: SpaceTokens.md, scroller: this.barScroller }) {
        // 编辑面即预览面：有据 EditableProfilePreview 原样（修改背景/修改头像双胶囊）
        ListItem() {
          EditableProfilePreview({
            avatar: this.avatar,
            avatarPreview: this.avatarPreview,
            nickname: this.nickname,
            bio: this.bio,
            selectedGender: String(this.currentGender()),
            profileId: 0,
            followingCount: this.tripCount,
            followerCount: this.badgeCount,
            totalLikes: this.cityCount,
            statLabels: ['行程', '勋章', '足迹'],
            profileBackground: this.profileBackground,
            profileBackgroundPreview: this.backgroundPreview,
            backgroundStatus: this.backgroundStatus,
            uploadingBackground: false,
            onPickBackground: (): void => {
              this.pickImage(false);
            },
            onPickAvatar: (): void => {
              this.pickImage(true);
            }
          })
        }

        // 昵称（必填 1-20，有据同款计数回显）
        ListItem() {
          Column({ space: SpaceTokens.xxs }) {
            this.fieldLabel('昵称', `${this.nickname.trim().length}/${NICKNAME_MAX}`, false)
            TextInput({ placeholder: '请输入昵称', text: this.nickname })
              .maxLength(NICKNAME_MAX)
              .fontSize(TypeTokens.callout.size)
              .fontColor(ColorTokens.ink)
              .placeholderColor(ColorTokens.muted)
              .backgroundColor(ColorTokens.surfaceSunken)
              .borderRadius(RadiusTokens.capsule)
              .height(LayoutTokens.composeFieldHeight)
              .onChange((v: string): void => {
                this.nickname = v;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 性别：官方 SegmentButton 三段，有据 EditProfilePage 同款控件
        ListItem() {
          Column({ space: SpaceTokens.xxs }) {
            Text('性别')
              .fontSize(TypeTokens.small.size)
              .fontWeight(600)
              .fontColor(ColorTokens.muted)
              .width('100%')
            Row() {
              SegmentButton({ options: this.genderOptions, selectedIndexes: $genderIndexes })
            }
            .width('100%')
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }

        // 简介：TextArea + 有据同款 100 字计数回显（选填）
        ListItem() {
          Column({ space: SpaceTokens.xxs }) {
            this.fieldLabel('简介', `${this.bio.length}/${BIO_MAX}`, this.bio.length >= BIO_MAX)
            TextArea({ placeholder: '介绍一下自己吧（选填）', text: this.bio })
              .maxLength(BIO_MAX)
              .fontSize(TypeTokens.callout.size)
              .fontColor(ColorTokens.ink)
              .placeholderColor(ColorTokens.muted)
              .backgroundColor(ColorTokens.surfaceSunken)
              .borderRadius(RadiusTokens.card)
              .height(LayoutTokens.composeFieldHeight * 2.4)
              .onChange((v: string): void => {
                this.bio = v;
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
        }
      }
      .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .contentStartOffset(HdsChrome.contentTopInset(this.statusBarHeight))
      .padding({
        left: SpaceTokens.base, right: SpaceTokens.base, bottom: SpaceTokens.xl
      })
      .onDidScroll((): void => {
        this.syncBarScroll();
      })
    }
    // HDS 深色档这层默认纯黑，透明栏会把它露成一条比画布暗一档的带（SettingsPage 同款）
    .backgroundColor(ColorTokens.canvas)
    .titleBar(HdsChrome.bar({ themeTick: this.chromeThemeTick,
      mainTitle: '编辑资料',
      scrolled: this.barScrolled,
      menu: [HdsChrome.item($r('sys.symbol.checkmark'), '保存', (): void => {
        this.onSave();
      })]
    }))
    .titleMode(HdsNavDestinationTitleMode.MINI)
    .bindToScrollable([this.barScroller])
    .clip(false)
    .onShown((): void => {
      this.loadAndFill();
    })
    // 脏态拦截（有据 onBack 同款 AlertDialog）；无改动直接放行系统默认返回
    .onBackPressed((): boolean => {
      this.onBack();
      return true;
    })
  }
}
