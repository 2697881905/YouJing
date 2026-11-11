/**
 * 分享导出（开发文档 §6 阶段 10：分享导出）。
 *
 * 无后端，所以「链接」做不了：这里走系统分享面板，三条通路都是本机现算的内容——
 * 1) 行程纯文本摘要（general.text）；2) 单个活动节点摘要（屏10，general.text）；
 * 3) 本机生成的 .ics 日历文件（general.file，
 * 写进 cacheDir 后交 fileUri，系统分享面板负责给接收方临时读权限）。
 * 不上传任何数据，不含账号信息。
 *
 * 例外（2026-11-11）：回顾海报的 AI 底图由 `ai/ImageGenClient` 向 BFF 发送
 * 「城市 + 风格」两个生成参数（见 pages/TripReviewPage）。本文件三条分享通路仍全程本机，
 * 图片产物不上传、不落服务端库。
 */

import { fileIo as fs, fileUri } from '@kit.CoreFileKit';
import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { Trip, TripDay, Activity } from '../model/Trip';
import { IcsBuilder } from '../utils/IcsBuilder';
import { Logger } from '../common/logger/Logger';

const TAG: string = 'Data.ShareExporter';

export class ShareExporter {
  /** 行程文本摘要 */
  static async shareSummary(context: common.UIAbilityContext, trip: Trip): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: IcsBuilder.plainSummary(trip),
      title: `${trip.destination} ${trip.days.length} 天行程`
    };
    await ShareExporter.present(context, new systemShare.SharedData(record));
  }

  /** 单个活动节点（屏10 详情面板的分享） */
  static async shareNode(context: common.UIAbilityContext, day: TripDay, act: Activity): Promise<void> {
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.PLAIN_TEXT,
      content: IcsBuilder.nodeSummary(day, act),
      title: `${act.title} ${act.time}`
    };
    await ShareExporter.present(context, new systemShare.SharedData(record));
  }

  /** 生成 .ics 落本机缓存并拉起分享；返回事件条数供界面回执 */
  static async shareIcs(context: common.UIAbilityContext, trip: Trip, advanceDays: number): Promise<number> {
    const text: string = IcsBuilder.build(trip, advanceDays);
    const path: string = `${context.cacheDir}/youjing-${trip.id}.ics`;
    if (fs.accessSync(path)) {
      fs.unlinkSync(path);
    }
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
    const uri: string = fileUri.getUriFromPath(path);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.FILE,
      uri: uri,
      title: `${trip.destination} 行程日历.ics`
    };
    await ShareExporter.present(context, new systemShare.SharedData(record));
    const events: number = trip.days.reduce((acc: number, d): number => acc + d.activities.length, 0);
    Logger.info(TAG, `导出 .ics events=${events} bytes=${text.length}`);
    return events;
  }

  /** 本机生成的回顾海报：只分享 cacheDir 里的图片，不申请相册权限、不落相册 */
  static async shareImage(context: common.UIAbilityContext, path: string, title: string): Promise<void> {
    const uri: string = fileUri.getUriFromPath(path);
    const record: systemShare.SharedRecord = {
      utd: uniformTypeDescriptor.UniformDataType.IMAGE,
      uri: uri,
      title: title
    };
    await ShareExporter.present(context, new systemShare.SharedData(record));
    Logger.info(TAG, `分享海报 ${title}`);
  }

  private static async present(context: common.UIAbilityContext, data: systemShare.SharedData): Promise<void> {
    const controller: systemShare.ShareController = new systemShare.ShareController(data);
    await controller.show(context, {
      previewMode: systemShare.SharePreviewMode.DETAIL,
      selectionMode: systemShare.SelectionMode.BATCH
    });
  }
}
