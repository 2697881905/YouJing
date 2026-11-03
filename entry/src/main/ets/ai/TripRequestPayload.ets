/**
 * BFF /v1/trip/generate 的 rich 请求载荷（端侧 SOT）。
 *
 * 字段与 PromptBuilder.userPrompt(params, spots, area) 的入参一一对应：
 * - 顶层：PlanParams.basic + 风格/档位/交通/节奏 + selectedArea + selectedSpots
 * - spots[]：完整 Spot（含 booking/provenance/坐标/停留时长/开放时间/周边）
 * - area：完整 Area（含 anchorStations/metroLines/airportMinutes/trainStationMinutes）
 *
 * BFF 的 rich 分支按同一套字段读取（bff/src/prompt/index.js）。改字段时：
 * 1) 先改这里（端侧 SOT）；
 * 2) 同步 bff 的 rich 分支；
 * 3) 跑 `cd bff && npm test`，`entry-payload-contract.test.js` 会拦字段漂移。
 *
 * 不伪造字段：Spot/Area 的缺失值按各自接口的 optional 语义保留 undefined，
 * JSON.stringify 会自动省略；BFF 若发现关键字段缺失会退回 sparse，而不是猜。
 */

import {
  PlanParams, SelectedSpot, TravelStyle, TransitPreference, PaceOption
} from '../model/PlanParams';
import { Spot } from '../model/Spot';
import { Area } from '../model/Area';

/** 端侧选中的住宿区域引用；同时带 id 与 name，BFF 两种都能读 */
export interface SelectedAreaRef {
  areaId: string;
  name: string;
}

/** 与 bff rich 分支一一对应的请求体 */
export interface TripGeneratePayload {
  destination: string;
  startDate: string;
  endDate: string;
  people: number;
  budget: number;
  style: TravelStyle;
  stayTier: string;
  transit: TransitPreference;
  paces: PaceOption[];
  selectedArea: SelectedAreaRef;
  selectedSpots: SelectedSpot[];
  /** 完整 Spot[]（含未选中的；BFF 只按 selectedSpots 取用） */
  spots: Spot[];
  /** 完整 Area */
  area: Area;
  passId?: string;
  freeTier: boolean;
}

export function buildTripGeneratePayload(params: PlanParams, spots: Spot[], area: Area,
  passId: string, freeTier: boolean): TripGeneratePayload {
  const selectedArea: SelectedAreaRef = {
    areaId: params.selectedArea.areaId,
    name: area.name
  };
  const payload: TripGeneratePayload = {
    destination: params.basic.destination,
    startDate: params.basic.startDate,
    endDate: params.basic.endDate,
    people: params.basic.people,
    budget: params.basic.budget,
    style: params.style,
    stayTier: params.stayTier,
    transit: params.transit,
    paces: params.paces,
    selectedArea,
    selectedSpots: params.selectedSpots,
    spots,
    area,
    freeTier
  };
  if (passId.length > 0) {
    payload.passId = passId;
  }
  return payload;
}
