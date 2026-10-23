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
import { ComingSoonPage } from './ComingSoonPage';

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
    GenerateFailedPage({
      code: typeof param === 'object' ? (param as FailInfo).code : 0,
      detail: typeof param === 'object' ? (param as FailInfo).detail : ''
    })
  } else if (name === 'EditItinerary') {
    EditItineraryPage({
      tripId: typeof param === 'object' ? (param as EditTarget).tripId : '',
      dayIndex: typeof param === 'object' ? (param as EditTarget).dayIndex : 0
    })
  } else if (name === 'Expense') {
    ExpensePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Trips') {
    TripsPage()
  } else if (name === 'OnTrip') {
    OnTripPage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Share') {
    SharePage({ tripId: typeof param === 'string' ? param as string : '' })
  } else if (name === 'Map') {
    ComingSoonPage({
      title: '地图视图',
      why: '真实底图要接华为地图服务（Map Kit），需先在 AppGallery Connect 开通并重新签名，'
        + '当前版本还没接。行程动线现在按时间线顺序呈现，每站的地址、通勤方式和耗时都在行程页里。'
    })
  } else {
    ComingSoonPage({ title: '这个视图', why: '还没有做出来。' })
  }
}

@Entry
@Component
struct Index {
  build() {
    Navigation(APP_NAV) {
      YoujingStartPage()
    }
    .navDestination(routerMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
    .backgroundColor($r('app.color.canvas'))
  }
}
