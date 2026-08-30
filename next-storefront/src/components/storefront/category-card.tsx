import Image from "next/image";
import Link from "next/link";
import { ArrowLeft, Gamepad2 } from "lucide-react";

import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardFooter, CardHeader, CardTitle } from "@/components/ui/card";
import type { StoreCategory } from "@/lib/supabase/catalog";

type CategoryCardProps = { category: StoreCategory };

export function CategoryCard({ category }: CategoryCardProps) {
  return (
    <Link
      href={`/category.html?id=${encodeURIComponent(category.id)}`}
      className="group block rounded-2xl outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-4"
      aria-label={`فتح قسم ${category.name}`}
    >
      <Card className="h-full overflow-hidden transition-[transform,border-color,box-shadow] duration-300 group-hover:-translate-y-1 group-hover:border-primary/30 group-hover:shadow-[0_24px_60px_-36px_rgba(255,106,26,0.35)]">
        <div className="relative aspect-[16/10] overflow-hidden bg-accent">
          {category.imageUrl ? (
            <Image
              src={category.imageUrl}
              alt={category.name}
              fill
              sizes="(max-width: 768px) 100vw, (max-width: 1200px) 50vw, 33vw"
              className="object-cover transition-transform duration-500 group-hover:scale-[1.04]"
            />
          ) : (
            <div className="grid h-full place-items-center">
              <div className="grid size-16 place-items-center rounded-2xl border border-primary/15 bg-background text-primary shadow-sm">
                <Gamepad2 className="size-8" strokeWidth={1.5} aria-hidden="true" />
              </div>
            </div>
          )}
          <div className="absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-foreground/20 to-transparent" />
          <Badge variant="secondary" className="absolute right-4 top-4 border-white/60 bg-white/90 text-foreground backdrop-blur">
            {category.productCount > 0 ? `${category.productCount} خيار` : "قريباً"}
          </Badge>
        </div>
        <CardHeader className="pb-2">
          <CardTitle className="text-xl">{category.name}</CardTitle>
        </CardHeader>
        <CardContent className="grow">
          <p className="line-clamp-2 min-h-12 text-sm leading-6 text-muted-foreground">
            {category.description || "اختر الباقة المناسبة وأكمل طلبك بخطوات واضحة وآمنة."}
          </p>
        </CardContent>
        <CardFooter className="justify-between border-t border-border/70 pt-4 text-sm font-extrabold text-primary">
          عرض الخيارات
          <ArrowLeft className="size-4 transition-transform group-hover:-translate-x-1" aria-hidden="true" />
        </CardFooter>
      </Card>
    </Link>
  );
}
