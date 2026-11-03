/** 测试夹具：一份能通过 TripParser 口径的合法 Trip */

export function validTrip() {
  return {
    id: 'trip-test',
    destination: '西安',
    startDate: '2026-11-06',
    endDate: '2026-11-06',
    people: 2,
    budget: 8000,
    style: 'leisure',
    overview: {
      totalCost: 500,
      highlights: ['碑林区一日'],
      summary: '测试行程'
    },
    days: [
      {
        dayIndex: 1,
        date: '2026-11-06',
        theme: '碑林区',
        intensity: 'low',
        dailyCost: 500,
        activities: [
          {
            id: 'a1',
            time: '09:00',
            endTime: '10:30',
            title: '西安城墙',
            location: '南门',
            address: '',
            longitude: 108.94,
            latitude: 34.26,
            status: 'not_booked',
            category: 'sight',
            transport: { mode: '步行', duration: 10, detail: '约 800m' }
          }
        ],
        meals: [
          { type: 'lunch', name: '午餐', time: '12:00', location: '碑林区', estimatedCost: 120 },
          { type: 'dinner', name: '晚餐', time: '18:00', location: '碑林区', estimatedCost: 180 }
        ],
        accommodation: '碑林区'
      }
    ],
    tips: ['预约信息以官方为准']
  };
}

/** 端侧当前真实会发的 sparse payload：只有景点名与区域名 */
export function sparseRequest() {
  return {
    destination: '西安',
    startDate: '2026-11-06',
    endDate: '2026-11-08',
    people: 2,
    budget: 8000,
    style: 'leisure',
    selectedSpots: ['西安城墙'],
    selectedArea: '碑林区',
    freeTier: false
  };
}

/** 未来端侧若补全景点/区域字段，BFF 不需要再改就能走 ets 同源 userPrompt */
export function richRequest() {
  return {
    destination: '西安',
    startDate: '2026-11-06',
    endDate: '2026-11-08',
    people: 2,
    budget: 8000,
    style: 'leisure',
    stayTier: 'comfort',
    transit: 'public',
    paces: ['standard'],
    selectedArea: { name: '碑林区' },
    selectedSpots: [{ name: '西安城墙', priority: 'must' }],
    area: {
      name: '碑林区',
      priceTier: 'comfort',
      metroLines: ['2号线'],
      anchorStations: ['永宁门'],
      airportMinutes: 45,
      trainStationMinutes: 12,
      source: 'seed'
    },
    spots: [
      {
        id: 's1',
        name: '西安城墙',
        city: '西安',
        tags: ['classic'],
        brief: '',
        suggestedDuration: 90,
        openingHours: '8:00–22:00',
        popularity: 100,
        nearbySpotIds: [],
        longitude: 108.94,
        latitude: 34.26,
        district: '碑林区',
        nearestMetro: '永宁门',
        booking: { requiresBooking: false },
        provenance: { source: 'seed', updatedAt: '2026-11-01' }
      }
    ]
  };
}
