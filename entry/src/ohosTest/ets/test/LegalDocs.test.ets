/**
 * 协议正文入口映射回归。
 *
 * 「我的」页设置行用的是 'terms'，登录页/同意弹窗用 'agreement'，
 * 两者必须落到同一份《用户协议》——曾经只有 'agreement' 被认，
 * 导致「我的 → 用户协议」点开是《隐私政策》全文。
 */

import { describe, it, expect, TestType, Size, Level } from '@ohos/hypium';
import { docOf, LegalSection } from '../../../main/ets/common/constants/LegalDocs';

export default function legalDocsTest(): void {
  describe('LegalDocs', () => {
    it('privacy_and_agreement_keep_their_own_doc', TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
      expect(docOf('privacy').title).assertEqual('隐私政策');
      expect(docOf('agreement').title).assertEqual('用户协议');
      expect(docOf('privacy').sections.length > 0).assertTrue();
      expect(docOf('agreement').sections.length > 0).assertTrue();
    });

    it('mine_page_terms_opens_the_agreement_not_the_privacy_policy',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        expect(docOf('terms').title).assertEqual('用户协议');
        expect(docOf('terms').sections.length).assertEqual(docOf('agreement').sections.length);
        expect(docOf('terms').sections[0].heading).assertEqual(docOf('agreement').sections[0].heading);
      });

    it('about_has_its_own_version_and_data_sources',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        const about = docOf('about');
        expect(about.title).assertEqual('关于有径');
        expect(about.sections.length > 0).assertTrue();
        const text: string = about.sections.map((s: LegalSection): string => s.heading + s.body).join('');
        // 版本、内置数据之外的地图来源、天气来源，三件都要说清，别退回空壳
        expect(text.indexOf('1.0.0') >= 0).assertTrue();
        expect(text.indexOf('Map Kit') >= 0).assertTrue();
        expect(text.indexOf('Open-Meteo') >= 0).assertTrue();
      });

    it('unknown_kind_falls_back_to_privacy_and_never_blank',
      TestType.FUNCTION | Size.SMALLTEST | Level.LEVEL1, () => {
        expect(docOf('').title).assertEqual('隐私政策');
        expect(docOf('whatever').sections.length > 0).assertTrue();
      });
  });
}
