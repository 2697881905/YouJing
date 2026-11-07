// 行程卡 → 行程详情「一镜到底」发起器（对齐有据 openPostDetailNav.ets 的安全口径）。
// 范式：目的地页自身变形，本处只负责「量卡片屏幕帧 + 截卡片图」并随 push 参数传出。
// 三条兜底照抄有据，每条都是踩出来的：
//   1) 量不到帧 → 没有起点就没有飞行，但**点击绝不能被吞掉**，立刻同步直推；
//   2) 截图是异步的、id 不存在时回调不保证触发 → 一次性放行标志 + 100ms 超时兜底；
//   3) 截图抛异常 → 照常推，退化为纯布局变形（官方注释：screenshot fails → default transition）。
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CardRect, cardRectOf } from './cardRect';
import { LongTakeParams } from './longTakeAnimationProperties';

/** push 参数：既要带业务 tripId，也要带转场几何。裸对象字面量在 ArkTS 里禁止，故显式类。 */
export class ItineraryNavParams {
  tripId: string = '';
  longTake: LongTakeParams | null = null;
}

/** 从路由参数里取 tripId：兼容旧的纯字符串深链与新的对象参数 */
export function tripIdOfParam(param: object): string {
  if (typeof param === 'string') {
    return param as string;
  }
  const p: ItineraryNavParams | null = param as ItineraryNavParams | null;
  return p !== null && p !== undefined && typeof p.tripId === 'string' ? p.tripId : '';
}

/** 从路由参数里取转场参数（旧深链没有 → null，目的地页据此不注册转场、按终态直接呈现） */
export function longTakeOfParam(param: object): LongTakeParams | null {
  if (typeof param === 'string') {
    return null;
  }
  const p: ItineraryNavParams | null = param as ItineraryNavParams | null;
  if (p === null || p === undefined) {
    return null;
  }
  const take: LongTakeParams | null = p.longTake;
  // 无有效卡片帧就不注册转场（有据 SearchPanelDestination.onReady 同判据）
  if (take === null || take === undefined || take.cardRect.width <= 0) {
    return null;
  }
  return take;
}

export function openItineraryLongTake(ui: UIContext, nav: NavPathStack, tripId: string,
  cardId: string, cardRadius: number): void {
  const p: ItineraryNavParams = new ItineraryNavParams();
  p.tripId = tripId;
  const rect: CardRect | null = cardRectOf(cardId);
  const take: LongTakeParams = new LongTakeParams();
  take.cardId = cardId;
  take.cardRadius = cardRadius;
  if (rect !== null) {
    take.cardRect = rect;
  }
  p.longTake = take;
  if (rect === null) {
    nav.pushPath({ name: 'Itinerary', param: p });
    return;
  }
  let pushed: boolean = false;
  const pushOnce: () => void = (): void => {
    if (pushed) {
      return;
    }
    pushed = true;
    nav.pushPath({ name: 'Itinerary', param: p });
  };
  setTimeout(pushOnce, 100);
  try {
    // UIContext 形态（@since 12）：全局 componentSnapshot.get 自 API 18 起废弃
    ui.getComponentSnapshot().get(cardId, (err: BusinessError, pixelMap: image.PixelMap): void => {
      if (!err && pixelMap !== undefined) {
        take.snapshot = pixelMap;
      }
      pushOnce();
    });
  } catch (e) {
    pushOnce();
  }
}
