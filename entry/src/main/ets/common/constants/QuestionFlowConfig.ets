/**
 * 偏好追问四题静态配置（开发文档 §4.2 + 屏3/3b 帧文案）。
 * Q1 五选项文案逐字取自屏3 定稿帧；Q2/Q3/Q4 帧内未出文案，
 * 按 §4.2 选项词 + 同语气补齐（占位文案，产品可一句话翻）。
 * defaultValues 即「用户不操作也能生成」的兜底（§4.2）。
 */

import { FlowQuestion } from '../../model/PlanParams';

export class QuestionFlowConfig {
  static readonly QUESTIONS: FlowQuestion[] = [
    {
      id: 'style',
      title: '这趟想怎么过？',
      helper: '只影响推荐排序，随时可改',
      multiSelect: false,
      defaultValues: ['leisure'],
      options: [
        { value: 'leisure', label: '休闲', desc: '一天 2–3 处，午后能坐下喝茶' },
        { value: 'fast_pace', label: '暴走', desc: '打卡核心机位，步数 20,000 起' },
        { value: 'family', label: '亲子', desc: '推车友好动线，间歇留足卫生间' },
        { value: 'foodie', label: '美食', desc: '以老铺与旬物排期，景点顺路看' },
        { value: 'culture', label: '文化', desc: '古迹深度停留，预留庭园观瞻耗时' }
      ]
    },
    {
      id: 'stay',
      title: '住得怎么舒服怎么来？',
      helper: '只影响区域推荐价位，随时可改',
      multiSelect: false,
      defaultValues: ['comfort'],
      options: [
        { value: 'economy', label: '经济型', desc: '干净能睡，把钱留给玩' },
        { value: 'comfort', label: '舒适型', desc: '通勤与环境的平衡档' },
        { value: 'luxury', label: '豪华型', desc: '位置与体验优先' }
      ]
    },
    {
      id: 'transit',
      title: '城里怎么移动？',
      helper: '影响动线串联与耗时计算',
      multiSelect: false,
      defaultValues: ['public'],
      options: [
        { value: 'public', label: '公共交通', desc: '地铁公交为主，跟着本地人走' },
        { value: 'taxi_main', label: '打车为主', desc: '点对点直达，省换乘体力' },
        { value: 'charter', label: '包车', desc: '行李与老人小孩友好' }
      ]
    },
    {
      id: 'pace',
      title: '每天走多满？',
      helper: '可多选，按天段分别排布',
      multiSelect: true,
      defaultValues: ['standard'],
      options: [
        { value: 'relaxed', label: '每天 3 个活动', desc: '轻松' },
        { value: 'standard', label: '每天 4–5 个', desc: '标准' },
        { value: 'packed', label: '每天 6 个以上', desc: '紧凑' }
      ]
    }
  ];
}
