/**
 * 真实底图组件（Map Kit）：把一组 MapStop 画成「落点 + 动线」，可复用在屏8 地图面板、
 * dock 地图页与屏5 片区卡。
 *
 * 三条口径写在这里，别改回「看起来更干净」的写法：
 * 1. MapComponent 的 mapOptions / mapCallback 缺一不建图，且 mapOptions 建时就要一个合法
 *    中心点，所以父组件必须在拿到首个可用坐标后再挂载本组件。
 * 2. Map Kit 在中国大陆用 GCJ02，喂 WGS84 会整体偏几百米——坐标由种子层转换后落库。
 * 3. 鉴权失败（如 1002600003）时底图只是空白、不报错，故必须自己兜一层带错误码的说明。
 */

import { map, mapCommon, MapComponent } from '@kit.MapKit';
import { AsyncCallback, Callback } from '@ohos.base';
import { BusinessError } from '@kit.BasicServicesKit';
import { MapBounds, MapStop, MapStops } from '../utils/MapStops';
import { NumberedPin } from '../utils/NumberedPin';
import { image } from '@kit.ImageKit';
import { Logger } from '../common/logger/Logger';
import { ColorTokens } from '../design/ColorTokens';
import { TypeTokens } from '../design/TypeTokens';
import { SpaceTokens } from '../design/SpaceTokens';
import { RadiusTokens } from '../design/RadiusTokens';

const TAG: string = 'Ui.Map';
/** 动线色对齐 route_path 档（浅色 #0066CC / 深色 #7DB8FF）：Map Kit 只吃 ARGB 数值 */
const LINE_LIGHT: number = 0xFF0066CC;
const LINE_DARK: number = 0xFF7DB8FF;
/** 图钉上的序号与动线同色，串给 canvas 用（'#AARRGGBB'） */
const PIN_BRAND_LIGHT: string = '#FF0066CC';
const PIN_BRAND_DARK: string = '#FF7DB8FF';
// newLatLngBounds 的留白单位是 px（不是 vp），且是**这块底图自己的** px。
// 图钉锚点在针尖，整枚图钉往点上方伸 ~260px（真机量的），所以顶部留白必须 ≥ 图钉高，
// 否则首站圆头被面板上边缘裁掉（把 260 改小到 120 就当场复现了）。
// 代价写在这里，别再往回改：小面板净高只有 625px，280+150 之后可视带只剩 ~195px，
// 两点相隔 7km 时镜头必然退到街区以上——这块面板的定位本来就是「当日动线概览」。
// 要更近的视角只能二选一：把图钉画小，或者把面板加高；满屏底图的地图页不受此限。
const FIT_PAD_TOP: number = 280;
const FIT_PAD_BOTTOM: number = 150;
const FIT_PAD_SIDE: number = 120;
const SINGLE_ZOOM: number = 15;
const DEFAULT_ZOOM: number = 11;
const FOCUS_ZOOM: number = 14;
const BEIJING_LAT: number = 39.9042;
const BEIJING_LNG: number = 116.4074;

@Component
export struct TripMapView {
  /** 落点集合；重铺以 signature 为准，数组本体只作单向拷贝 */
  @Prop @Watch('redraw') stops: MapStop[] = [];
  /** 内容指纹：数组 @Prop 的变更时机不可靠，标量键才是重铺的准绳 */
  @Prop @Watch('redraw') signature: string = '';
  /** 父组件下发的镜头指令：'fit' 或 'focus:<index>:<seq>'（seq 让重复点同一项也能触发） */
  @Prop @Watch('onRequest') request: string = '';
  /** 落点之间是否连线：行程要连，屏5 的三片候选是互斥选项、连起来就成了动线 */
  @Prop route: boolean = true;
  /**
   * 全览留白（px，与 newLatLngBounds 同单位）：由宿主按自己盖在底图上的浮层量出来传，
   * 因为底图是满屏的、浮层不是。默认值按屏8 那块 625px 高的小面板量的，别当全局值用。
   */
  @Prop fitTopPx: number = FIT_PAD_TOP;
  @Prop fitBottomPx: number = FIT_PAD_BOTTOM;
  /** 点落点时回调（MapStop.index，1 起），父组件据此同步列表高亮 */
  onStopClick?: (index: number) => void;
  @StorageProp('isDarkMode') @Watch('applyTheme') isDark: boolean = false;
  @State private ready: boolean = false;
  @State private mapError: string = '';
  private controller: map.MapComponentController | null = null;
  private events: map.MapEventManager | null = null;
  private markers: map.Marker[] = [];
  private lines: map.MapPolyline[] = [];
  private drawn: string = '';
  private options: mapCommon.MapOptions = TripMapView.initialOptions(BEIJING_LAT, BEIJING_LNG);
  private onMarkerClick: Callback<map.Marker> = (marker: map.Marker | undefined): void => {
    // MapKit 在组件拆除期会用 undefined 再回调一次；直接 getTag 抛 TypeError 会把整个进程带走
    if (marker === undefined || marker === null) {
      return;
    }
    const idx: number = Number(`${marker.getTag()}`);
    if (this.onStopClick !== undefined && Number.isInteger(idx) && idx > 0) {
      this.onStopClick(idx);
    }
  };
  private onCreated: AsyncCallback<map.MapComponentController> =
    (err: BusinessError, ctrl: map.MapComponentController): void => {
      if (err !== undefined && err !== null) {
        this.mapError = `底图初始化失败（${err.code}）`;
        Logger.error(TAG, `MapComponent 初始化失败 code=${err.code} msg=${err.message}`);
        return;
      }
      this.controller = ctrl;
      this.events = ctrl.getEventManager();
      this.events.on('markerClick', this.onMarkerClick);
      this.mapError = '';
      this.ready = true;
      this.applyTheme();
      this.redraw();
    };

  private static initialOptions(lat: number, lng: number): mapCommon.MapOptions {
    const target: mapCommon.LatLng = { latitude: lat, longitude: lng };
    const position: mapCommon.CameraPosition = { target: target, zoom: DEFAULT_ZOOM };
    const opts: mapCommon.MapOptions = {
      position: position,
      zoomControlsEnabled: false,
      compassControlsEnabled: false,
      scaleControlsEnabled: false,
      myLocationControlsEnabled: false,
      tiltGesturesEnabled: false,
      rotateGesturesEnabled: false
    };
    return opts;
  }

  aboutToAppear(): void {
    if (this.stops.length > 0) {
      this.options = TripMapView.initialOptions(this.stops[0].latitude, this.stops[0].longitude);
    }
  }

  aboutToDisappear(): void {
    // 拆除期底图的原生侧已在回收：注销与清理覆盖物都可能抛异常，异常逃出这里就是 JS 崩溃、进程被杀
    if (this.events !== null) {
      try {
        this.events.off('markerClick', this.onMarkerClick);
      } catch (err) {
        Logger.warn(TAG, `注销 markerClick 异常: ${(err as BusinessError).message}`);
      }
      this.events = null;
    }
    try {
      this.clearOverlays();
    } catch (err) {
      Logger.warn(TAG, `清理覆盖物异常: ${(err as BusinessError).message}`);
    }
    this.controller = null;
  }

  /** 父组件指令入口：'fit' 回全览，'focus:<index>:<seq>' 飞到某个落点 */
  onRequest(): void {
    if (this.controller === null || this.request.length === 0) {
      return;
    }
    if (this.request.startsWith('fit')) {
      this.controller.moveCamera(this.cameraFor(this.stops));
      return;
    }
    if (!this.request.startsWith('focus:')) {
      return;
    }
    const idx: number = Number(this.request.split(':')[1]);
    const hit: MapStop | undefined = this.stops.find((s: MapStop): boolean => s.index === idx);
    if (hit !== undefined) {
      this.controller.animateCamera(TripMapView.latLngUpdate(hit, FOCUS_ZOOM), 400);
    }
  }

  applyTheme(): void {
    if (this.controller !== null) {
      this.controller.setDayNightMode(
        this.isDark ? mapCommon.DayNightMode.NIGHT : mapCommon.DayNightMode.DAY);
    }
  }

  private static latLngUpdate(stop: MapStop, zoom: number): map.CameraUpdate {
    const point: mapCommon.LatLng = { latitude: stop.latitude, longitude: stop.longitude };
    return map.newLatLng(point, zoom);
  }

  private cameraFor(stops: MapStop[]): map.CameraUpdate {
    if (stops.length === 1) {
      return TripMapView.latLngUpdate(stops[0], SINGLE_ZOOM);
    }
    const box: MapBounds | null = MapStops.bounds(stops);
    if (box === null) {
      return map.newLatLng({ latitude: BEIJING_LAT, longitude: BEIJING_LNG } as mapCommon.LatLng, DEFAULT_ZOOM);
    }
    const bounds: mapCommon.LatLngBounds = {
      southwest: { latitude: box.minLat, longitude: box.minLng },
      northeast: { latitude: box.maxLat, longitude: box.maxLng }
    };
    const pad: mapCommon.Padding = {
      left: FIT_PAD_SIDE, right: FIT_PAD_SIDE, top: this.fitTopPx, bottom: this.fitBottomPx
    };
    return map.newLatLngBounds(bounds, pad);
  }

  private clearOverlays(): void {
    for (const marker of this.markers) {
      marker.remove();
    }
    this.markers = [];
    for (const line of this.lines) {
      line.remove();
    }
    this.lines = [];
    this.drawn = '';
  }

  redraw(): void {
    const ctrl: map.MapComponentController | null = this.controller;
    if (ctrl === null) {
      return;
    }
    const key: string = this.signature.length > 0 ? this.signature : MapStops.signature(this.stops);
    if (key === this.drawn) {
      return;
    }
    this.drawn = key;
    this.clearOverlays();
    const stops: MapStop[] = this.stops.filter((s: MapStop): boolean => MapStops.usable(s.latitude, s.longitude));
    if (stops.length === 0) {
      Logger.warn(TAG, '无可用落点，底图保持空白');
      return;
    }
    const runs: MapStop[][] = MapStops.runs(stops);
    runs.forEach((run: MapStop[], r: number): void => {
      if (!this.route || run.length < 2) {
        return;
      }
      const runPoints: mapCommon.LatLng[] =
        run.map((s: MapStop): mapCommon.LatLng => { return { latitude: s.latitude, longitude: s.longitude }; });
      const lineOpts: mapCommon.MapPolylineOptions = {
        points: runPoints,
        width: 6,
        color: this.isDark ? LINE_DARK : LINE_LIGHT,
        clickable: false,
        geodesic: false
      };
      ctrl.addPolyline(lineOpts).then((line: map.MapPolyline): void => {
        this.lines.push(line);
      }).catch((err: BusinessError): void => {
        Logger.error(TAG, `第 ${r + 1} 段动线绘制失败 code=${err.code} msg=${err.message}`);
      });
    });
    const brand: string = this.isDark ? PIN_BRAND_DARK : PIN_BRAND_LIGHT;
    const pending: Promise<map.Marker>[] = stops.map((s: MapStop): Promise<map.Marker> => {
      const opts: mapCommon.MarkerOptions = {
        position: { latitude: s.latitude, longitude: s.longitude },
        title: `${s.index}. ${s.title}`,
        snippet: s.subtitle,
        clickable: true,
        anchorU: 0.5,
        anchorV: 1
      };
      // 序号画进官方图钉槽位；生成失败时不设 icon，退回默认图钉
      const pin: image.PixelMap | undefined = NumberedPin.of(s.index, brand);
      if (pin !== undefined) {
        opts.icon = pin;
      }
      return ctrl.addMarker(opts);
    });
    Promise.all(pending).then((markers: map.Marker[]): void => {
      if (this.controller === null) {
        // 落点是异步生成的，回来时组件可能已经拆掉，底图对象失效
        Logger.warn(TAG, '底图已拆除，丢弃本次落点生成结果');
        return;
      }
      markers.forEach((marker: map.Marker, i: number): void => {
        marker.setTag(`${stops[i].index}`);
      });
      this.markers = markers;
      ctrl.moveCamera(this.cameraFor(stops));
    }).catch((err: BusinessError): void => {
      Logger.error(TAG, `落点绘制失败 code=${err.code} msg=${err.message}`);
      this.mapError = `落点绘制失败（${err.code}）`;
    });
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 底图必须先挂载才会有 mapCallback；ready 只能由回调置真，
      // 拿 ready 当挂载条件会自锁（首版真机就踩在这里：地图永远不出来）
      MapComponent({ mapOptions: this.options, mapCallback: this.onCreated })
        .width('100%')
        .height('100%')
      if (this.mapError.length > 0) {
        Column({ space: SpaceTokens.xs }) {
          Text('底图没出来')
            .fontSize(TypeTokens.body.size)
            .fontWeight(600)
            .fontColor(ColorTokens.ink)
          Text(`${this.mapError}；行程内容不受影响，可继续看时间线`)
            .fontSize(TypeTokens.caption.size)
            .fontColor(ColorTokens.muted)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .padding({ left: SpaceTokens.xl, right: SpaceTokens.xl })
        .backgroundColor(ColorTokens.surfaceSubtle)
      } else if (!this.ready) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ColorTokens.surfaceSubtle)
      }
    }
    .width('100%')
    .height('100%')
    .borderRadius(RadiusTokens.card)
    .clip(true)
  }
}
