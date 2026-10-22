/**
 * 应用根 · Navigation 容器（handoff §12 路由表）。
 * 屏1 首启页为导航栏内容（栈空即首启），其余路由经 routerMap 分发。
 * 未落地路由统一进 ComingSoon 占位，主链批次内保持可点闭环。
 */

import { APP_NAV } from '../common/constants/AppNav';
import { YoujingStartPage } from './YoujingStartPage';
import { TripInputPage } from './TripInputPage';
import { PreferenceQAPage } from './PreferenceQAPage';
import { SpotPickPage } from './SpotPickPage';
import { StayPickPage } from './StayPickPage';
import { GeneratingPage } from './GeneratingPage';
import { ItineraryPage } from './ItineraryPage';
import { GenerateFailedPage } from './GenerateFailedPage';
import { EditItineraryPage } from './EditItineraryPage';
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
    ItineraryPage()
  } else if (name === 'GenerateFailed') {
    GenerateFailedPage()
  } else if (name === 'EditItinerary') {
    EditItineraryPage()
  } else {
    ComingSoonPage({ routeName: name })
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
