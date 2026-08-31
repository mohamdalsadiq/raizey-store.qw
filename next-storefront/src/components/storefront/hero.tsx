"use client";

import Link from "next/link";
import { ArrowLeft, BadgeCheck, ScanLine, ShieldCheck, Sparkles, Zap } from "lucide-react";
import { motion, useReducedMotion } from "motion/react";

import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";

type HeroProps = {
  categoryCount: number;
  productCount: number;
};

const trustPoints = [
  { icon: ShieldCheck, label: "دفع محمي" },
  { icon: Zap, label: "تنفيذ سريع" },
  { icon: BadgeCheck, label: "دعم موثوق" },
];

export function Hero({ categoryCount, productCount }: HeroProps) {
  const reduceMotion = useReducedMotion();
  const initial = reduceMotion ? false : { opacity: 0, y: 16 };

  return (
    <section className="container-shell py-8 sm:py-12 lg:py-16">
      <div className="hero-surface grid overflow-hidden rounded-[2rem] border border-border lg:grid-cols-[minmax(0,1.12fr)_minmax(330px,0.88fr)]">
        <motion.div
          initial={initial}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.55, ease: [0.22, 1, 0.36, 1] }}
          className="flex flex-col justify-center px-6 py-10 sm:px-10 sm:py-14 lg:px-14 lg:py-20"
        >
          <Badge className="mb-6">
            <Sparkles className="size-3.5" aria-hidden="true" />
            تجربة رقمية أذكى وأوضح
          </Badge>
          <h1 className="max-w-2xl text-balance text-4xl font-black leading-[1.18] tracking-[-0.035em] text-foreground sm:text-5xl lg:text-[3.75rem]">
            شحناتك الرقمية،
            <span className="text-primary"> بدون تعقيد.</span>
          </h1>
          <p className="mt-5 max-w-xl text-pretty text-base leading-8 text-muted-foreground sm:text-lg">
            اختر الخدمة المناسبة، أكمل بياناتك بأمان، وتابع طلبك من مكان واحد بتجربة مصممة لتكون سريعة وواضحة.
          </p>
          <div className="mt-8 flex flex-col gap-3 sm:flex-row">
            <Button asChild size="lg">
              <Link href="#storefront">
                تصفح المتجر
                <ArrowLeft data-icon aria-hidden="true" />
              </Link>
            </Button>
            <Button asChild variant="secondary" size="lg">
              <Link href="/my-orders.html">تتبع طلبك</Link>
            </Button>
          </div>
          <div className="mt-9 flex flex-wrap gap-x-6 gap-y-3 border-t border-border pt-6">
            {trustPoints.map(({ icon: Icon, label }) => (
              <div key={label} className="flex items-center gap-2 text-sm font-bold text-muted-foreground">
                <Icon className="size-4 text-primary" aria-hidden="true" />
                {label}
              </div>
            ))}
          </div>
        </motion.div>

        <motion.div
          initial={reduceMotion ? false : { opacity: 0, scale: 0.97 }}
          animate={{ opacity: 1, scale: 1 }}
          transition={{ duration: 0.6, delay: reduceMotion ? 0 : 0.08, ease: [0.22, 1, 0.36, 1] }}
          className="relative m-3 min-h-[390px] overflow-hidden rounded-[1.55rem] bg-foreground p-6 text-white sm:m-5 sm:min-h-[450px] sm:p-9 lg:m-6"
        >
          <div className="relative flex h-full flex-col">
            <div className="flex items-start justify-between gap-4">
              <div>
                <p className="text-xs font-bold tracking-wide text-white/55">RAIZEY SMART CHECK</p>
                <h2 className="mt-2 text-2xl font-black">الفحص الذكي للدفع</h2>
              </div>
              <span className="flex items-center gap-2 rounded-full border border-white/10 bg-white/8 px-3 py-1.5 text-xs font-bold text-white/80">
                <span className="size-2 rounded-full bg-success shadow-[0_0_0_5px_rgba(59,183,126,0.12)]" />
                متاح
              </span>
            </div>

            <div className="my-auto grid place-items-center py-8">
              <div className="relative grid size-36 place-items-center rounded-[2rem] border border-primary/35 bg-primary/10 sm:size-44">
                <span className="absolute inset-3 rounded-[1.5rem] border border-dashed border-primary/45" />
                <ScanLine className="size-16 text-primary sm:size-20" strokeWidth={1.35} aria-hidden="true" />
                <span className="scan-line absolute left-6 right-6 h-px bg-primary shadow-[0_0_16px_2px_rgba(255,106,26,0.7)]" />
              </div>
            </div>

            <div className="relative grid grid-cols-2 gap-3">
              <div className="rounded-2xl border border-white/10 bg-white/[0.06] p-4 backdrop-blur-sm">
                <p className="text-2xl font-black">{categoryCount || "—"}</p>
                <p className="mt-1 text-xs font-bold text-white/55">تصنيفات نشطة</p>
              </div>
              <div className="rounded-2xl border border-white/10 bg-white/[0.06] p-4 backdrop-blur-sm">
                <p className="text-2xl font-black">{productCount || "—"}</p>
                <p className="mt-1 text-xs font-bold text-white/55">خيارات متاحة</p>
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </section>
  );
}
