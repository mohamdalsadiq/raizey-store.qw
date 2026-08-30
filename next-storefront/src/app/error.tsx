"use client";

import { AlertCircle, RotateCcw } from "lucide-react";

import { Button } from "@/components/ui/button";

export default function ErrorPage({ reset }: { error: Error & { digest?: string }; reset: () => void }) {
  return (
    <main className="container-shell grid min-h-[70vh] place-items-center py-12">
      <div className="max-w-lg text-center">
        <div className="mx-auto grid size-14 place-items-center rounded-2xl bg-primary/10 text-primary">
          <AlertCircle className="size-7" aria-hidden="true" />
        </div>
        <h1 className="mt-6 text-2xl font-black">حدث خطأ غير متوقع</h1>
        <p className="mt-3 leading-7 text-muted-foreground">
          لم نتمكن من إكمال تحميل الصفحة. يمكنك إعادة المحاولة الآن.
        </p>
        <Button onClick={reset} className="mt-7">
          <RotateCcw data-icon aria-hidden="true" />
          إعادة المحاولة
        </Button>
      </div>
    </main>
  );
}
