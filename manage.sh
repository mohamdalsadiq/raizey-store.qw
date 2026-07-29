#!/bin/bash

git config --global --add safe.directory '*' 2>/dev/null
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "======================================"
echo "       🚀 لوحة التحكم بـ raizey-store  "
echo "======================================"
echo "1) 🧹 حذف جميع ملفات المشروع من GitHub"
echo "2) 📦 فك ضغط ملف ZIP ورفعه (بدون حذف القديم)"
echo "3) 🚀 رفع التغيرات الحالية مباشرة"
echo "4) 🔴 تفريغ كامل + فك ZIP جديد + رفع"
echo "======================================"
read -p "اختر الرقم المطلوب (1-4): " choice

case $choice in
    1)
        echo "🧹 جاري حذف جميع ملفات المشروع..."
        find . -mindepth 1 -maxdepth 1 ! -name '.git' ! -name 'manage.sh' -exec rm -rf {} +
        git add -A
        git commit -m "حذف جميع ملفات المشروع"
        git push origin "$BRANCH"
        echo "✅ تم تفريغ المشروع وحذفه من GitHub بنجاح!"
        ;;
    2)
        read -p "أدخل مسار ملف الـ ZIP: " zpath
        if [ -f "$zpath" ]; then
            echo "📦 جاري فك الضغط..."
            unzip -o "$zpath" -d .
            find . -maxdepth 2 -type f -name "index.html" -exec dirname {} \; | grep -v '^\.$' | while read dir; do
                mv "$dir"/* . 2>/dev/null
                rm -rf "$dir"
            done
            git add -A
            git commit -m "إضافة ملفات جديدة من ZIP"
            git push origin "$BRANCH"
            echo "✅ تم رفع الملفات الجديدة بنجاح!"
        else
            echo "❌ ملف الـ ZIP غير موجود!"
        fi
        ;;
    3)
        echo "🚀 جاري رفع جميع التغيرات الحالية..."
        git add -A
        read -p "أدخل وصف التحديث (أو اضغط Enter): " msg
        if [ -z "$msg" ]; then msg="تحديث الملفات"; fi
        git commit -m "$msg"
        git push origin "$BRANCH"
        echo "✅ تم الرفع بنجاح!"
        ;;
    4)
        read -p "أدخل مسار ملف الـ ZIP: " zpath
        if [ -f "$zpath" ]; then
            echo "🧹 جاري تفريغ المشروع..."
            find . -mindepth 1 -maxdepth 1 ! -name '.git' ! -name 'manage.sh' -exec rm -rf {} +
            echo "📦 جاري فك الضغط..."
            unzip -o "$zpath" -d .
            # ترتيب الملفات في المجلد الرئيسي تلقائياً إذا كانت داخل مجلد فرعي
            find . -maxdepth 2 -type f -name "index.html" -exec dirname {} \; | grep -v '^\.$' | while read dir; do
                mv "$dir"/* . 2>/dev/null
                rm -rf "$dir"
            done
            git add -A
            git commit -m "استبدال كامل للمشروع"
            git push origin "$BRANCH"
            echo "✅ تم استبدال المشروع بالكامل ورفعه!"
        else
            echo "❌ الملف غير موجود!"
        fi
        ;;
    *)
        echo "❌ خيار غير صحيح!"
        ;;
esac
