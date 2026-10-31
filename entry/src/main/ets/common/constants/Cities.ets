/**
 * 支持城市单点定义：屏2 城市列表、种子导入、一句话解析共用同一份。
 * 京都只存在于演示 mock（MockConfig 开关），不进正式支持列表。
 */

export interface CityDef {
  name: string;
  spotsFile: string;
  areasFile: string;
}

export const CITY_DEFS: CityDef[] = [
  { name: '北京', spotsFile: 'seed/spots_beijing.jsonl', areasFile: 'seed/areas_beijing.jsonl' },
  { name: '上海', spotsFile: 'seed/spots_shanghai.jsonl', areasFile: 'seed/areas_shanghai.jsonl' },
  { name: '广州', spotsFile: 'seed/spots_guangzhou.jsonl', areasFile: 'seed/areas_guangzhou.jsonl' },
  { name: '深圳', spotsFile: 'seed/spots_shenzhen.jsonl', areasFile: 'seed/areas_shenzhen.jsonl' },
  // 杨凌：用户本人所在地，拿来当"真实用户视角"的测试城。
  // 坐标是按公开资料里**街道/村镇位置**给的近似值（与 DistrictCoords 同一档精度），
  // 精确经纬度待地理编码回填；`lines` 用公交线名，因为杨凌没有轨道交通。
  { name: '杨凌', spotsFile: 'seed/spots_yangling.jsonl', areasFile: 'seed/areas_yangling.jsonl' }
];

export const SUPPORTED_CITIES: string[] = CITY_DEFS.map((c: CityDef): string => c.name);

/** 城市面板的热门快捷入口：全部走 Map Kit，不冒充内置种子城市 */
export const POPULAR_MAP_CITIES: string[] = [
  '西安', '成都', '杭州', '重庆', '南京', '武汉', '长沙', '厦门'
];

export interface MapCityAlias {
  alias: string;
  city: string;
}

/** 一句话里的常见城市别称 → Map Kit 城市；只收不易误伤的词 */
export const MAP_CITY_ALIASES: MapCityAlias[] = [
  { alias: '蓉城', city: '成都' },
  { alias: '山城', city: '重庆' },
  { alias: '金陵', city: '南京' },
  { alias: '江城', city: '武汉' },
  { alias: '星城', city: '长沙' },
  { alias: '鹭岛', city: '厦门' },
  { alias: '春城', city: '昆明' },
  { alias: '冰城', city: '哈尔滨' },
  { alias: '泉城', city: '济南' },
  { alias: '岛城', city: '青岛' }
];

/**
 * 是否走 Map Kit 任意城市检索：内置五城与京都 mock 之外的都算。
 * 只决定「种子库为空时要不要联网取数」，不校验城市名是否真实；取不到会走 1004 失败出口。
 */
export function isMapCity(city: string): boolean {
  const name: string = city.trim();
  return name.length > 0 && SUPPORTED_CITIES.indexOf(name) < 0 && name.indexOf('京都') < 0;
}

export interface CityAlias {
  alias: string;
  city: string;
}

/** 只收不会误伤的别称：单字「京/沪/深」太容易命中散文，不进来 */
export const CITY_ALIASES: CityAlias[] = [
  { alias: '京城', city: '北京' },
  { alias: '帝都', city: '北京' },
  { alias: '魔都', city: '上海' },
  { alias: '沪上', city: '上海' },
  { alias: '羊城', city: '广州' },
  { alias: '穗城', city: '广州' },
  { alias: '鹏城', city: '深圳' },
  { alias: '杨陵', city: '杨凌' }
];

/**
 * 常见但非种子的城市：一句话里出现时交给 Map Kit 兜底（Stage 2），
 * 不再直接拒绝；名单不追求穷尽，城市面板的「其他城市」可输入任意名称。
 */
export const UNSUPPORTED_CITIES: string[] = [
  '西安', '成都', '杭州', '重庆', '南京', '武汉', '长沙', '苏州', '厦门', '青岛',
  '大连', '昆明', '大理', '丽江', '三亚', '桂林', '天津', '郑州', '济南', '哈尔滨',
  '沈阳', '长春', '福州', '南昌', '合肥', '太原', '石家庄', '兰州', '西宁', '银川',
  '乌鲁木齐', '拉萨', '呼和浩特', '张家界', '黄山', '洛阳', '开封', '平遥', '敦煌',
  '九寨沟', '婺源', '珠海', '佛山', '东莞', '无锡', '常州', '宁波', '温州', '绍兴',
  '嘉兴', '扬州', '烟台', '威海', '秦皇岛', '承德', '大同', '延安', '宝鸡', '咸阳',
  '天水', '张掖', '嘉峪关', '西双版纳', '香格里拉', '阳朔', '北海', '泉州', '景德镇',
  '宜昌', '襄阳', '恩施', '岳阳', '韶山', '曲阜', '泰安', '日照', '淄博', '邯郸',
  '保定', '唐山', '鄂尔多斯', '呼伦贝尔', '延吉', '丹东'
];
