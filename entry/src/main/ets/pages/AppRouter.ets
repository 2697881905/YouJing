/**
 * 全局路由表（§12）。从 `pages/Index.ets` 抽出来是给「tab 根页内联」铺路：
 * 根页一旦自带内嵌 HdsNavigation（有据路线 B），它也得挂 `.navDestination(...)`，
 * 而 routerMap 留在 Index 里会让 Index ↔ 页面互相 import 成环。
 *
 * 落点归属：`ComingSoonPage` 的 else 分支是全仓唯一的「没认出来的路由名」出口，
 * debug 包把名字直接画进标题——真机 dumpLayout 就能读到是谁推了不存在的落点
 * （@Builder 体内不许写普通语句，日志式探针编译不过 10905204，只能走 UI）。
 */

import { EditTarget, FailInfo } from '../common/constants/AppNav';
import { TripInputPage } from './TripInputPage';
import { PreferenceQAPage } from './PreferenceQAPage';
import { SpotPickPage } from './SpotPickPage';
import { StayPickPage } from './StayPickPage';
import { GeneratingPage } from './GeneratingPage';
import { ItineraryPage } from './ItineraryPage';
import { GenerateFailedPage } from './GenerateFailedPage';
import { EditItineraryPage } from './EditItineraryPage';
import { ExpensePage } from './ExpensePage';
import { TripsPage } from './TripsPage';
import { OnTripPage } from './OnTripPage';
import { SharePage } from './SharePage';
import { MapPage } from './MapPage';
import { AreaMorePage } from './AreaMorePage';
import { ComingSoonPage } from './ComingSoonPage';
import { BadgePage } from './BadgePage';
import { TripReviewPage } from './TripReviewPage';
import { PricingPage } from './PricingPage';
import { BuildConfig } from '../common/constants/BuildConfig';

/**
 * 路由参数窄化（@Builder 内不允许局部 const，故放普通函数）：
 * typeof null === 'object'，必须先排掉 null 再断言，
 * 否则深链不带参数直达会抛 TypeError。
 */
function asFailInfo(param: object): FailInfo {
  const fallback: FailInfo = { code: 0, detail: '' };
  return (typeof param === 'object' && param !== null) ? param as FailInfo : fallback;
}

function asEditTarget(param: object): EditTarget {
  const fallback: EditTarget = { tripId: '', dayIndex: 0 };
  return (typeof param === 'object' && param !== null) ? param as EditTarget : fallback;
}

function tripIdOf(param: object): string {
  return typeof param === 'string' ? param as string : '';
}

@Builder
export function routerMap(name: string, param: object) {
  if (name === 'TripInput') {
    TripInputPage()
  } else if (name === 'PreferenceQA') {
    PreferenceQAPage()
  } else if (name === 'SpotPick') {
    SpotPickPage()
  } else if (name === 'StayPick') {
    StayPickPage()
  } else if (name === 'Generating') {
    GeneratingPage()
  } else if (name === 'Itinerary') {
    ItineraryPage({ tripId: tripIdOf(param) })
  } else if (name === 'GenerateFailed') {
    GenerateFailedPage({ code: asFailInfo(param).code, detail: asFailInfo(param).detail })
  } else if (name === 'EditItinerary') {
    EditItineraryPage({ tripId: asEditTarget(param).tripId, dayIndex: asEditTarget(param).dayIndex })
  } else if (name === 'Expense') {
    ExpensePage({ tripId: tripIdOf(param) })
  } else if (name === 'Trips') {
    TripsPage()
  } else if (name === 'OnTrip') {
    OnTripPage({ tripId: tripIdOf(param) })
  } else if (name === 'Share') {
    SharePage({ tripId: tripIdOf(param) })
  } else if (name === 'AreaMore') {
    AreaMorePage({ city: tripIdOf(param) })
  } else if (name === 'Map') {
    MapPage({ tripId: tripIdOf(param) })
  } else if (name === 'Badges') {
    BadgePage()
  } else if (name === 'Review') {
    TripReviewPage({ tripId: tripIdOf(param) })
  } else if (name === 'Pricing') {
    PricingPage({ tripId: tripIdOf(param) })
  } else {
    ComingSoonPage({
      title: BuildConfig.IS_DEBUG ? `未识别路由 [${name}]` : '这个页面'
    })
  }
}
