#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
RAIZEY STORE — مولّد صور إيصالات اختبارية لاختبار خط أنابيب الفحص الحقيقي.

يُنشئ لقطات شاشة (PNG) تحاكي إشعارات تحويل:
  bankak.png  — بنكك (بنك الخرطوم)
  ocash.png   — أوكاش (بنك أم درمان الوطني)
  fawry.png   — فوري
  not_receipt.png  — صورة بلا أي نص (يجب أن تُرفض)
  noise.png        — ضجيج عشوائي (يجب أن تُرفض)

النصوص تستخدم نفس التسميات الموجودة في قواميس receipt-judge-core.ts حتى
يقيس الاختبار خط الأنابيب الحقيقي لا improvisation.

الاستخدام:
    python3 scripts/live_receipt_fixtures.py <output_dir>

المتطلبات: pillow, arabic-reshaper, python-bidi + خط عربي TTF (يُمرَّر
بالوسيط الثاني أو متغير البيئة RAIZEY_FIXTURE_FONT).
"""
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFont
import arabic_reshaper
from bidi.algorithm import get_display

# الخط يجب أن يغطي "أشكال العرض العربية" (Arabic Presentation Forms-B،
# النطاق U+FE70–U+FEFF) كاملة، لأن arabic_reshaper يحوّل الحروف إلى هذه
# الأشكال و Pillow بدون libraqm لا يطبق تشكيل GSUB. خط ناقص التغطية يرسم
# مربعات فارغة فتقرأ Gemini نصاً مشوّهاً (مثل "فايز الصا") ويفشل مطابقة
# اسم المستفيد. المقاس الفعلي: NotoNaskh = 141/141، Amiri = 140، Cairo = 89.
FONT_PATH = os.environ.get("RAIZEY_FIXTURE_FONT", "/tmp/livecheck/NotoNaskh.ttf")

# حساب الاستقبال الحقيقي لمتجر رايزي في وسيلة الدفع "بنكك"
# (payment_methods.account_name / bin_prefixes) — يجعل الإيصال الاختباري
# مطابقاً لإيصال عميل حقيقي بدل حساب وهمي.
RECEIVER_NAME_AR = "فايزه الصادق هارون البشاري"
RECEIVER_BIN = "57040290563000001"
W = 760
MARGIN = 34
INK = (17, 20, 26)
MUTED = (120, 128, 140)
LINE = (223, 227, 234)
BG = (255, 255, 255)


def ar(text):
    """تشكيل عربي صحيح + ترتيب RTL."""
    return get_display(arabic_reshaper.reshape(text))


def load(size):
    return ImageFont.truetype(FONT_PATH, size)


class Sheet:
    def __init__(self, accent):
        self.accent = accent
        self.h = 1240
        self.img = Image.new("RGB", (W, self.h), BG)
        self.d = ImageDraw.Draw(self.img)
        self.y = 0
        self.f_title = load(38)
        self.f_sub = load(20)
        self.f_label = load(21)
        self.f_value = load(21)
        self.f_small = load(16)

    def band(self, title, subtitle):
        self.d.rectangle([0, 0, W, 150], fill=self.accent)
        self.d.text((W - MARGIN, 34), ar(title), font=self.f_title, fill=(255, 255, 255), anchor="ra")
        self.d.text((W - MARGIN, 92), ar(subtitle), font=self.f_sub, fill=(255, 255, 255), anchor="ra")
        self.y = 186

    def section(self, text):
        self.d.text((W - MARGIN, self.y), ar(text), font=self.f_sub, fill=self.accent, anchor="ra")
        self.y += 34
        self.d.line([MARGIN, self.y, W - MARGIN, self.y], fill=LINE, width=2)
        self.y += 16

    def row(self, label, value, strong=False, value_color=None, arabic_value=False):
        """سطر واحد بتخطيط RTL حقيقي: التسمية في أقصى اليمين ثم القيمة
        ملاصقة لها على نفس السطر (كما في إشعارات البنوك الفعلية).

        الفصل بين التسمية والقيمة على طرفي الشاشة يجعل قارئ الصور يقرأهما
        كسطرين منفصلين، فلا يستطيع الحكم ربط الاسم بقيمته.
        """
        label_font = self.f_label
        self.d.text((W - MARGIN, self.y), ar(label), font=label_font, fill=MUTED, anchor="ra")
        if value:
            gap = 18
            label_w = self.d.textlength(ar(label), font=label_font)
            value_x = W - MARGIN - label_w - gap
            self.d.text(
                (value_x, self.y),
                ar(value) if arabic_value else value,
                font=load(24) if strong else self.f_value,
                fill=value_color or INK,
                anchor="ra",
            )
        self.y += 44
        self.d.line([MARGIN, self.y - 10, W - MARGIN, self.y - 10], fill=LINE, width=1)

    def status(self, text, ok=True):
        self.y += 6
        color = (11, 128, 71) if ok else (190, 30, 45)
        self.d.rounded_rectangle([MARGIN, self.y, W - MARGIN, self.y + 62], radius=12, fill=color)
        self.d.text((W // 2, self.y + 16), ar(text), font=load(26), fill=(255, 255, 255), anchor="ma")
        self.y += 86

    def footer(self, lines):
        for line in lines:
            self.d.text((W - MARGIN, self.y), ar(line), font=self.f_small, fill=MUTED, anchor="ra")
            self.y += 26

    def save(self, path):
        self.img.crop((0, 0, W, min(self.h, self.y + MARGIN))).save(path, "PNG", optimize=True)
        print(f"wrote {path} ({os.path.getsize(path)} bytes)")


def bankak(path):
    s = Sheet((15, 61, 122))  # بنك الخرطوم — كحلي
    s.band("بنكك", "بنك الخرطوم — إشعار تحويل")
    s.section("تحويلات")
    s.row("رقم العملية", "FT250719123456", strong=True)
    s.row("التاريخ و الزمن", "2026-10-04 11:32:05")
    # اسم المستفيد ورقم BIN يجب أن يطابقا حساب الاستقبال الحقيقي المسجّل في
    # payment_methods، وإلا أطلق الحكم الأعلام bin_mismatch /
    # beneficiary_name_unverified (سلوك مقصود في الإنتاج).
    s.row("اسم المرسل اليه", RECEIVER_NAME_AR, arabic_value=True)
    s.row("من حساب", "2050111223344")
    s.row("الى حساب", RECEIVER_BIN)
    s.row("رقم الموبايل", "0912345678")
    s.row("المبلغ", "125,000.00 SDG", strong=True, value_color=(15, 61, 122))
    s.row("التعليق", "شراء منتجات")
    s.status("عملية ناجحة")
    s.footer(["هذا إشعار آلي من تطبيق بنكك", "لا حاجة للرد على هذه الرسالة"])
    s.save(path)


def ocash(path):
    s = Sheet((88, 34, 138))  # أوكاش — بنفسجي
    s.band("أوكاش", "بنك أم درمان الوطني")
    s.section("تفاصيل الحركة")
    s.row("رقم الحركة", "121004123456789", strong=True)
    s.row("تاريخ الحركة", "2026-10-04 09:15:22")
    s.row("نوع الحركة", "تحويل", arabic_value=True)
    s.row("اسم العميل", "عبدالله محمد ابراهيم", arabic_value=True)
    s.row("قيمة الحركة", "48,500.00 SDG", strong=True, value_color=(88, 34, 138))
    s.row("رقم الهاتف المحمول", "0991234567")
    s.row("مقدم الخدمة", "زين السودان")
    s.row("التحويل الى حساب مصرفي", "1234567890")
    s.row("الحساب المحلي", "1234567890")
    s.status("حركة ناجحة")
    s.footer(["أوكاش — لكل الناس", "خدمة العملاء 1555"])
    s.save(path)


def fawry(path):
    s = Sheet((180, 40, 22))  # فوري — أحمر
    s.band("فوري", "Fawry — إشعار دفع")
    s.section("تفاصيل العملية")
    s.row("الرقم المرجعي", "987654321012", strong=True)
    s.row("اسم المستفيد", "سارة ابراهيم حسن", arabic_value=True)
    s.row("من الحساب", "1122334455")
    s.row("اسم البنك", "بنك البركة", arabic_value=True)
    s.row("المبلغ", "23,750.00 SDG", strong=True, value_color=(180, 40, 22))
    s.row("رقم الهاتف", "0911223344")
    s.row("التاريخ", "2026-10-04 16:40")
    s.row("التعليق", "دفع فاتورة")
    s.status("ناجح")
    s.footer(["فوري — شبكة المدفوعات", "Fawry reference 987654321012"])
    s.save(path)


def not_receipt(path):
    img = Image.new("RGB", (W, 900), (244, 240, 232))
    d = ImageDraw.Draw(img)
    for i in range(0, 900, 6):
        d.line([0, i, W, i], fill=(236 + (i % 6), 230 + (i % 5), 220 + (i % 4)), width=3)
    d.ellipse([190, 250, 570, 630], fill=(70, 110, 150))
    d.ellipse([250, 330, 340, 420], fill=(250, 250, 250))
    d.ellipse([420, 330, 510, 420], fill=(250, 250, 250))
    d.arc([300, 440, 460, 560], start=20, end=160, fill=(250, 250, 250), width=12)
    img.save(path, "PNG", optimize=True)
    print(f"wrote {path} ({os.path.getsize(path)} bytes) — no text at all")


def noise(path):
    random.seed(20261005)
    img = Image.new("RGB", (W, 700))
    img.putdata([(random.randint(0, 255), random.randint(0, 255), random.randint(0, 255)) for _ in range(W * 700)])
    img.save(path, "PNG", optimize=True)
    print(f"wrote {path} ({os.path.getsize(path)} bytes) — random noise")


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/livecheck/fixtures"
    os.makedirs(out, exist_ok=True)
    if not os.path.exists(FONT_PATH):
        sys.exit(f"Arabic TTF not found: {FONT_PATH} (set RAIZEY_FIXTURE_FONT)")
    bankak(os.path.join(out, "bankak.png"))
    ocash(os.path.join(out, "ocash.png"))
    fawry(os.path.join(out, "fawry.png"))
    not_receipt(os.path.join(out, "not_receipt.png"))
    noise(os.path.join(out, "noise.png"))


if __name__ == "__main__":
    main()
