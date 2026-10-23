/**
 * 内置景点库 DAO：批量 upsert + 按城市读取（阶段 5 数据灌入通道）。
 */

import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { DatabaseHelper } from './DatabaseHelper';
import { Spot, SpotTag } from '../model/Spot';

function parseTags(text: string): SpotTag[] {
  if (text.length === 0) {
    return [];
  }
  try {
    return JSON.parse(text) as SpotTag[];
  } catch (err) {
    return [];
  }
}

export class SpotDao {
  static saveSpots(context: common.Context, spots: Spot[]): Promise<void> {
    return DatabaseHelper.write(context, async (store: relationalStore.RdbStore): Promise<void> => {
      for (const s of spots) {
        const row: relationalStore.ValuesBucket = {
          id: s.id, name: s.name, city: s.city, tags: JSON.stringify(s.tags),
          brief: s.brief, suggested_duration: s.suggestedDuration, popularity: s.popularity,
          nearby_ids: JSON.stringify(s.nearbySpotIds), longitude: s.longitude, latitude: s.latitude,
          district: s.district, nearest_metro: s.nearestMetro,
          entrance_tip: s.entranceTip === undefined ? null : s.entranceTip,
          requires_booking: s.booking.requiresBooking ? 1 : 0,
          booking_method: s.booking.bookingMethod === undefined ? null : s.booking.bookingMethod,
          advance_days: s.booking.advanceDays === undefined ? null : s.booking.advanceDays,
          release_time: s.booking.releaseTime === undefined ? null : s.booking.releaseTime,
          closed_day: s.booking.closedDay === undefined ? null : s.booking.closedDay,
          difficulty: s.booking.difficulty === undefined ? null : s.booking.difficulty,
          source: s.provenance.source, updated_at: s.provenance.updatedAt
        };
        store.insertSync('spot', row, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
      }
    });
  }

  static async loadByCity(context: common.Context, city: string): Promise<Spot[]> {
    const store: relationalStore.RdbStore = await DatabaseHelper.getStore(context);
    const rs: relationalStore.ResultSet =
      await store.querySql('SELECT * FROM spot WHERE city = ? ORDER BY popularity DESC', [city]);
    const out: Spot[] = [];
    try {
      while (rs.goToNextRow()) {
        const tip: string = rs.getString(rs.getColumnIndex('entrance_tip'));
        const method: string = rs.getString(rs.getColumnIndex('booking_method'));
        const release: string = rs.getString(rs.getColumnIndex('release_time'));
        const closed: string = rs.getString(rs.getColumnIndex('closed_day'));
        const diff: string = rs.getString(rs.getColumnIndex('difficulty'));
        let nearby: string[] = [];
        try {
          nearby = JSON.parse(rs.getString(rs.getColumnIndex('nearby_ids'))) as string[];
        } catch (err) {
          nearby = [];
        }
        const spot: Spot = {
          id: rs.getString(rs.getColumnIndex('id')),
          name: rs.getString(rs.getColumnIndex('name')),
          city: rs.getString(rs.getColumnIndex('city')),
          tags: parseTags(rs.getString(rs.getColumnIndex('tags'))),
          brief: rs.getString(rs.getColumnIndex('brief')),
          suggestedDuration: rs.getLong(rs.getColumnIndex('suggested_duration')),
          popularity: rs.getLong(rs.getColumnIndex('popularity')),
          nearbySpotIds: nearby,
          longitude: rs.getDouble(rs.getColumnIndex('longitude')),
          latitude: rs.getDouble(rs.getColumnIndex('latitude')),
          district: rs.getString(rs.getColumnIndex('district')),
          nearestMetro: rs.getString(rs.getColumnIndex('nearest_metro')),
          entranceTip: tip.length > 0 ? tip : undefined,
          booking: {
            requiresBooking: rs.getLong(rs.getColumnIndex('requires_booking')) === 1,
            bookingMethod: method.length > 0 ? method : undefined,
            advanceDays: rs.isColumnNull(rs.getColumnIndex('advance_days'))
              ? undefined : rs.getLong(rs.getColumnIndex('advance_days')),
            releaseTime: release.length > 0 ? release : undefined,
            closedDay: closed.length > 0 ? closed : undefined,
            difficulty: diff.length > 0 ? diff : undefined
          },
          provenance: {
            source: rs.getString(rs.getColumnIndex('source')),
            updatedAt: rs.getString(rs.getColumnIndex('updated_at'))
          }
        };
        out.push(spot);
      }
    } finally {
      rs.close();
    }
    return out;
  }
}
