/**
 * 内置住宿区域库 DAO：批量 upsert + 按城市读取。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { Area, AreaGroup, AreaPriceTier } from '../model/Area';

function parseArr(text: string): string[] {
  if (text.length === 0) {
    return [];
  }
  try {
    return JSON.parse(text) as string[];
  } catch (err) {
    return [];
  }
}

export class AreaDao {
  static saveAreas(context: common.UIAbilityContext, areas: Area[]): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      for (const a of areas) {
        const row: relationalStore.ValuesBucket = {
          id: a.id, name: a.name, city: a.city, longitude: a.longitude, latitude: a.latitude,
          description: a.description, anchor_stations: JSON.stringify(a.anchorStations),
          metro_lines: JSON.stringify(a.metroLines), airport_minutes: a.airportMinutes,
          train_station_minutes: a.trainStationMinutes, commerce_tags: JSON.stringify(a.commerceTags),
          dining_density: a.diningDensity, suitable_crowds: JSON.stringify(a.suitableCrowds),
          price_tier: a.priceTier, price_range: a.priceRange === undefined ? null : a.priceRange,
          grp: a.group, source: a.source, updated_at: a.updatedAt
        };
        store.insertSync('area', row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    });
  }

  static async loadByCity(context: common.UIAbilityContext, city: string): Promise<Area[]> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM area WHERE city = ?', [city]);
    const out: Area[] = [];
    try {
      while (rs.goToNextRow()) {
        const range: string = rs.getString(rs.getColumnIndex('price_range'));
        const area: Area = {
          id: rs.getString(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
          city: rs.getString(rs.getColumnIndex('city')),
          longitude: rs.getDouble(rs.getColumnIndex('longitude')),
          latitude: rs.getDouble(rs.getColumnIndex('latitude')),
          description: rs.getString(rs.getColumnIndex('description')),
          anchorStations: parseArr(rs.getString(rs.getColumnIndex('anchor_stations'))),
          metroLines: parseArr(rs.getString(rs.getColumnIndex('metro_lines'))),
          airportMinutes: rs.getLong(rs.getColumnIndex('airport_minutes')),
          trainStationMinutes: rs.getLong(rs.getColumnIndex('train_station_minutes')),
          commerceTags: parseArr(rs.getString(rs.getColumnIndex('commerce_tags'))),
          diningDensity: rs.getString(rs.getColumnIndex('dining_density')),
          suitableCrowds: parseArr(rs.getString(rs.getColumnIndex('suitable_crowds'))),
          priceTier: rs.getString(rs.getColumnIndex('price_tier')) as AreaPriceTier,
          priceRange: range.length > 0 ? range : undefined,
          group: rs.getString(rs.getColumnIndex('grp')) as AreaGroup,
          source: rs.getString(rs.getColumnIndex('source')),
          updatedAt: rs.getString(rs.getColumnIndex('updated_at'))
        };
        out.push(area);
      }
    } finally {
      rs.close();
    }
    return out;
  }
}
