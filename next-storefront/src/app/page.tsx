import Image from "next/image";
import Link from "next/link";
import {
  ArrowLeft,
  BadgeCheck,
  CircleDollarSign,
  Headphones,
  PackageCheck,
  SearchCheck,
  ShieldCheck,
  WalletCards,
  Zap,
} from "lucide-react";

import { CategoryCard } from "@/components/storefront/category-card";
import { Hero } from "@/components/storefront/hero";
import { SiteHeader } from "@/components/storefront/site-header";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Separator } from "@/components/ui/separator";
import { getCatalog } from "@/lib/supabase/catalog";

const steps = [
  {
    icon: SearchCheck,
    number: "01",
    title: "اختر خدمتك",
    description: "تصفح الأقسام وحدد الباقة التي تناسب احتياجك.",
  },
  {
    icon: ShieldCheck,
    number: "02",
    title: "أدخل بياناتك بأمان",
    description: "نطلب فقط المعلومات الضرورية لتنفيذ الطلب.",
  },
  {
    icon: PackageCheck,
    number: "03",
    title: "تابع التنفيذ",
    description: "تحقق من حالة الطلب حتى اكتماله من حسابك.",
  },
];

const promises = [
  { icon: Zap, title: "سرعة واضحة", text: "خطوات قصيرة من الاختيار إلى تأكيد الطلب" },
  { icon: BadgeCheck, title: "خدمات موثوقة", text: "خيارات منظمة ومراجعة قبل عرضها" },
  { icon: Headphones, title: "دعم قريب", text: "مساعدة عند الحاجة بدون تعقيد" },
];

export const revalidate = 300;

export default async function Home() {
  const catalog = await getCatalog();
  const productCount = catalog.categories.reduce((sum, category) => sum + category.productCount, 0);
  const categoriesBySection = new Map<string, typeof catalog.categories>();

  for (const category of catalog.categories) {
    const sectionCategories = categoriesBySection.get(category.sectionId) ?? [];
    sectionCategories.push(category);
    categoriesBySection.set(category.sectionId, sectionCategories);
  }

  return (
    <>
      <SiteHeader />
      <main>
        <Hero categoryCount={catalog.categories.length} productCount={productCount} />

        <section className="border-y border-border bg-card/70">
          <div className="container-shell grid gap-0 sm:grid-cols-3">
            {promises.map(({ icon: Icon, title, text }, index) => (
              <div
                key={title}
                className={`flex items-center gap-4 py-5 sm:px-5 ${index > 0 ? "border-t border-border sm:border-r sm:border-t-0" : ""}`}
              >
                <div className="grid size-11 shrink-0 place-items-center rounded-xl bg-primary/10 text-primary">
                  <Icon className="size-5" aria-hidden="true" />
                </div>
                <div>
                  <p className="text-sm font-extrabold">{title}</p>
                  <p className="mt-1 text-xs leading-5 text-muted-foreground">{text}</p>
                </div>
              </div>
            ))}
          </div>
        </section>

        <section id="storefront" className="container-shell scroll-mt-24 py-16 sm:py-20 lg:py-24">
          <div className="mb-10 flex flex-col justify-between gap-5 sm:flex-row sm:items-end">
            <div>
              <Badge variant="outline" className="mb-4">المتجر</Badge>
              <h2 className="text-3xl font-black tracking-[-0.025em] sm:text-4xl">ابدأ من القسم المناسب</h2>
              <p className="mt-3 max-w-xl leading-7 text-muted-foreground">
                خدمات مرتبة بوضوح حتى تصل إلى ما تحتاجه بأقل عدد من الخطوات.
              </p>
            </div>
            <Button asChild variant="ghost" className="w-fit text-primary">
              <Link href="/search.html">
                البحث في كل الخدمات
                <ArrowLeft data-icon aria-hidden="true" />
              </Link>
            </Button>
          </div>

          {!catalog.configured ? (
            <CatalogNotice
              title="جاهزون لعرض بيانات المتجر"
              description="أضف متغيرات Supabase العامة إلى بيئة التشغيل لعرض الأقسام والمنتجات الفعلية."
            />
          ) : catalog.error ? (
            <CatalogNotice
              title="تعذر تحميل المتجر الآن"
              description="حدث خلل مؤقت أثناء قراءة الأقسام. حدّث الصفحة أو حاول بعد قليل."
            />
          ) : catalog.categories.length === 0 ? (
            <CatalogNotice
              title="الأقسام قيد التجهيز"
              description="ستظهر الخدمات هنا فور تفعيلها من لوحة الإدارة."
            />
          ) : (
            <div className="space-y-14">
              {catalog.sections.map((section) => {
                const categories = categoriesBySection.get(section.id) ?? [];
                if (categories.length === 0) return null;

                return (
                  <section key={section.id} aria-labelledby={`section-${section.id}`}>
                    <div className="mb-6 flex items-center gap-4">
                      <span className="h-8 w-1 rounded-full bg-primary" aria-hidden="true" />
                      <h3 id={`section-${section.id}`} className="text-xl font-black sm:text-2xl">
                        {section.name}
                      </h3>
                      <Separator className="flex-1" />
                    </div>
                    <div className="grid items-stretch gap-5 md:grid-cols-2 xl:grid-cols-3">
                      {categories.map((category) => (
                        <CategoryCard key={category.id} category={category} />
                      ))}
                    </div>
                  </section>
                );
              })}
            </div>
          )}
        </section>

        <section id="how-it-works" className="scroll-mt-24 bg-foreground py-16 text-white sm:py-20 lg:py-24">
          <div className="container-shell">
            <div className="max-w-2xl">
              <Badge className="border-white/10 bg-white/8 text-white">ببساطة</Badge>
              <h2 className="mt-5 text-3xl font-black tracking-[-0.025em] sm:text-4xl">طلبك في ثلاث خطوات</h2>
              <p className="mt-3 leading-7 text-white/55">مسار شراء واضح يزيل التخمين ويترك لك المهم فقط.</p>
            </div>
            <div className="mt-10 grid gap-4 lg:grid-cols-3">
              {steps.map(({ icon: Icon, number, title, description }) => (
                <Card key={number} className="border-white/10 bg-white/[0.055] text-white shadow-none">
                  <CardHeader className="flex-row items-start justify-between gap-4">
                    <div className="grid size-12 place-items-center rounded-xl bg-primary text-white">
                      <Icon className="size-6" aria-hidden="true" />
                    </div>
                    <span className="text-3xl font-black text-white/12">{number}</span>
                  </CardHeader>
                  <CardContent>
                    <CardTitle className="text-xl">{title}</CardTitle>
                    <p className="mt-3 text-sm leading-7 text-white/55">{description}</p>
                  </CardContent>
                </Card>
              ))}
            </div>
          </div>
        </section>

        <section className="container-shell py-16 sm:py-20 lg:py-24">
          <div className="relative overflow-hidden rounded-[2rem] border border-primary/15 bg-accent px-6 py-10 sm:px-10 sm:py-14 lg:flex lg:items-center lg:justify-between lg:px-14">
            <div className="relative max-w-2xl">
              <div className="mb-5 grid size-12 place-items-center rounded-xl bg-primary text-white">
                <WalletCards className="size-6" aria-hidden="true" />
              </div>
              <h2 className="text-3xl font-black tracking-[-0.025em] sm:text-4xl">رصيدك جاهز حين تحتاجه</h2>
              <p className="mt-3 leading-7 text-muted-foreground">
                اشحن محفظتك مرة واحدة واستخدم رصيدك لتسريع مشترياتك القادمة.
              </p>
            </div>
            <div className="relative mt-8 flex flex-col gap-3 sm:flex-row lg:mt-0 lg:flex-col">
              <Button asChild size="lg">
                <Link href="/wallet.html">
                  <CircleDollarSign data-icon aria-hidden="true" />
                  فتح المحفظة
                </Link>
              </Button>
              <Button asChild variant="secondary" size="lg">
                <Link href="/wallet.html">شحن الرصيد</Link>
              </Button>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-border bg-card">
        <div className="container-shell grid gap-10 py-12 md:grid-cols-[1.4fr_1fr_1fr]">
          <div>
            <Image
              src="/brand/raizey-logo.png"
              width={1202}
              height={344}
              alt="RAIZEY STORE"
              className="h-auto w-40"
            />
            <p className="mt-4 max-w-sm text-sm leading-7 text-muted-foreground">
              متجر رقمي سوداني بتجربة مرتبة، واضحة، وآمنة من أول اختيار حتى اكتمال طلبك.
            </p>
          </div>
          <FooterLinks title="روابط سريعة" links={[["المتجر", "#storefront"], ["طلباتي", "/my-orders.html"], ["المحفظة", "/wallet.html"]]} />
          <FooterLinks title="المساعدة" links={[["سياسة الخصوصية", "/privacy.html"], ["برنامج الإحالة", "/referrals.html"], ["تسجيل الدخول", "/login.html"]]} />
        </div>
        <div className="container-shell border-t border-border py-5 text-center text-xs text-muted-foreground sm:text-right">
          © {new Date().getFullYear()} RAIZEY STORE. جميع الحقوق محفوظة.
        </div>
      </footer>
    </>
  );
}

function CatalogNotice({ title, description }: { title: string; description: string }) {
  return (
    <div className="rounded-2xl border border-dashed border-primary/30 bg-accent p-8 text-center sm:p-12">
      <div className="mx-auto grid size-12 place-items-center rounded-xl bg-primary/10 text-primary">
        <SearchCheck className="size-6" aria-hidden="true" />
      </div>
      <h3 className="mt-5 text-xl font-black">{title}</h3>
      <p className="mx-auto mt-2 max-w-lg text-sm leading-7 text-muted-foreground">{description}</p>
    </div>
  );
}

function FooterLinks({ title, links }: { title: string; links: [string, string][] }) {
  return (
    <div>
      <h2 className="text-sm font-black">{title}</h2>
      <ul className="mt-4 grid gap-3">
        {links.map(([label, href]) => (
          <li key={href}>
            <Link href={href} className="text-sm text-muted-foreground transition-colors hover:text-primary">
              {label}
            </Link>
          </li>
        ))}
      </ul>
    </div>
  );
}
