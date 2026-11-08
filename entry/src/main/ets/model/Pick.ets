/**
 * P1 AI 精选契约（端侧 ↔ BFF/云函数）。
 * 只交换「候选 + 排序 + 一句理由」；不搬完整 Spot/Area，省 token 也压缩幻觉面。
 */

export interface PickCandidate {
  id: string;
  name: string;
  tag: string;
  brief: string;
  district: string;
  popularity: number;
  suggestedDuration: number;
  requiresBooking: boolean;
}

export interface PickRankItem {
  id: string;
  reason: string;
}

export interface PickResult {
  ranked: PickRankItem[];
  note: string;
}
