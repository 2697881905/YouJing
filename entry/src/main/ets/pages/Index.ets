/**
 * 应用根 · Navigation 容器（handoff §12 路由表）。
 * 屏1 首启页为导航栏内容（栈空即首启），其余路由经 routerMap 分发。
 * 未落地路由统一进 ComingSoon 占位，主链批次内保持可点闭环。
 */

import { APP_NAV, EditTarget, FailInfo } from '../common/constants/AppNav';
import { YoujingStartPage } from './YoujingStartPage';
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
import { HdsNavigation } from '@kit.UIDesignKit';

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

@Builder
function routerMap(name: string, param: object) {
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
    ItineraryPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'GenerateFailed') {
    GenerateFailedPage({ code: asFailInfo(param).code, detail: asFailInfo(param).detail })
  } else if (name === 'EditItinerary') {
    EditItineraryPage({ tripId: asEditTarget(param).tripId, dayIndex: asEditTarget(param).dayIndex })
  } else if (name === 'Expense') {
    ExpensePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Trips') {
    TripsPage()
  } else if (name === 'OnTrip') {
    OnTripPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Share') {
    SharePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'AreaMore') {
    AreaMorePage({ city: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Map') {
    MapPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else {
    ComingSoonPage()
  }
}

@Entry
@Component
struct Index {
  build() {
    HdsNavigation(APP_NAV) {
      YoujingStartPage()
    }
    .navDestination(routerMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.canvas'))
  }
}
