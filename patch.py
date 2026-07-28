import re

with open('admin.html', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace product modal body
old_prod_body_pattern = r'<div class="modal-body">\s*<input type="hidden" id="editProdId">.*?</div>\s*<div class="modal-footer">'
new_prod_body = """<div class="modal-body">
        <input type="hidden" id="editProdId">
        <div class="form-group"><label for="prodCategorySelect">التصنيف</label><select id="prodCategorySelect"></select></div>
        <div class="form-group"><label for="prodName">اسم المنتج</label><input type="text" id="prodName" placeholder="مثلاً: 60 UC أو اشتراك رقمي"></div>
        <div class="form-group"><label for="prodShortDesc">الوصف المختصر</label><input type="text" id="prodShortDesc" placeholder="يظهر في قائمة المنتجات للعميل"></div>
        <div class="form-group"><label for="prodDesc">شرح المنتج / طريقة الاستلام</label><textarea id="prodDesc" placeholder="يشرح للعميل كيف يستلم الخدمة"></textarea></div>
        <div class="form-group">
          <label>صورة المنتج</label>
          <div class="upload-shell">
            <div class="upload-actions">
              <button class="btn btn-primary" type="button" onclick="document.getElementById('productImageFile').click()"><i class="fa-solid fa-camera"></i><span>📷 رفع صورة</span></button>
              <button class="btn btn-secondary" type="button" onclick="document.getElementById('productImageFile').click()"><i class="fa-solid fa-repeat"></i><span>تغيير</span></button>
            </div>
            <input type="file" id="productImageFile" accept="image/*" hidden onchange="handleImageSelection(this,'product')">
            <div id="productUploadStatus" class="upload-status">اختر صورة وسيتم رفعها مباشرة إلى Supabase Storage.</div>
            <div id="productPreviewWrap" class="preview-wrap">
              <img id="productImagePreview" class="preview-img" alt="معاينة صورة المنتج">
              <div class="preview-meta">
                <strong id="productPreviewLabel">معاينة الصورة</strong>
                <div id="productImageLink" class="preview-link"></div>
                <div class="action-btns">
                  <button class="action-btn accent" type="button" onclick="copyImageLink('product')"><i class="fa-solid fa-link"></i><span>نسخ رابط الصورة</span></button>
                  <button class="action-btn" type="button" onclick="document.getElementById('productImageFile').click()"><i class="fa-solid fa-pen"></i><span>تغيير</span></button>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="form-group"><label for="prodPrice">السعر بالدولار ($)</label><input type="number" step="0.01" id="prodPrice" placeholder="مثال: 5.99"></div>
        <div class="form-group">
          <div class="toggle-container" style="padding: 0 0 10px">
            <div><strong style="display:block">إضافة خيارات فرعية للمنتج</strong><p class="section-copy" style="margin:0">سيكون اختيار أحد الخيارات إجبارياً على الزبون عند الشراء</p></div>
            <label class="switch"><input type="checkbox" id="prodHasOptions" onchange="toggleOptionsSection(this.checked)"><span class="slider"></span></label>
          </div>
          <div id="prodOptionsSection" style="display: none; background: rgba(255,255,255,.02); padding: 12px; border-radius: 12px; border: 1px solid var(--border);">
            <div id="prodOptionsList" class="item-list" style="margin-bottom: 12px;"></div>
            <button class="action-btn primary" type="button" onclick="addProdOption()"><i class="fa-solid fa-plus"></i><span>إضافة خيار جديد</span></button>
          </div>
        </div>
        <div class="form-group"><label for="prodDisplayOrder">ترتيب العرض</label><input type="number" id="prodDisplayOrder" placeholder="مثال: 1"></div>
        <div class="form-group">
          <label for="prodStatus">الحالة</label>
          <select id="prodStatus">
            <option value="active">فعال</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
        <div class="form-group">
          <label>البيانات المطلوبة من العميل عند الشراء</label>
          <div id="prodRequiredFieldsList" class="item-list" style="margin-bottom: 12px;"></div>
          <button class="action-btn primary" type="button" onclick="addProdRequiredField()"><i class="fa-solid fa-plus"></i><span>إضافة حقل مطلوب</span></button>
        </div>
      </div>
      <div class="modal-footer">"""
content = re.sub(old_prod_body_pattern, new_prod_body, content, flags=re.DOTALL)


# Replace category modal body
old_cat_body_pattern = r'<div class="modal-body">\s*<input type="hidden" id="editCatId">.*?</div>\s*<div class="modal-footer">'
new_cat_body = """<div class="modal-body">
        <input type="hidden" id="editCatId">
        <div class="form-group"><label for="catName">اسم التصنيف</label><input type="text" id="catName" placeholder="مثلاً: ببجي موبايل"></div>
        <div class="form-group"><label for="catDesc">وصف التصنيف</label><textarea id="catDesc" placeholder="وصف التصنيف..."></textarea></div>
        <div class="form-group">
          <label>صورة التصنيف</label>
          <div class="upload-shell">
            <div class="upload-actions">
              <button class="btn btn-primary" type="button" onclick="document.getElementById('categoryImageFile').click()"><i class="fa-solid fa-camera"></i><span>📷 رفع صورة</span></button>
              <button class="btn btn-secondary" type="button" onclick="document.getElementById('categoryImageFile').click()"><i class="fa-solid fa-repeat"></i><span>تغيير</span></button>
            </div>
            <input type="file" id="categoryImageFile" accept="image/*" hidden onchange="handleImageSelection(this,'category')">
            <div id="categoryUploadStatus" class="upload-status">يمكنك عرض الصورة الحالية أو رفع صورة جديدة مباشرة.</div>
            <div id="categoryPreviewWrap" class="preview-wrap">
              <img id="categoryImagePreview" class="preview-img" alt="معاينة صورة التصنيف">
              <div class="preview-meta">
                <strong id="categoryPreviewLabel">معاينة الصورة</strong>
                <div id="categoryImageLink" class="preview-link"></div>
                <div class="action-btns">
                  <button class="action-btn accent" type="button" onclick="copyImageLink('category')"><i class="fa-solid fa-link"></i><span>نسخ رابط الصورة</span></button>
                  <button class="action-btn" type="button" onclick="document.getElementById('categoryImageFile').click()"><i class="fa-solid fa-pen"></i><span>تغيير</span></button>
                </div>
              </div>
            </div>
          </div>
        </div>
        <div class="form-group"><label for="catDisplayOrder">ترتيب العرض</label><input type="number" id="catDisplayOrder" placeholder="مثال: 1"></div>
        <div class="form-group"><label for="catCommission">نسبة عمولة الإحالة (%)</label><input type="number" step="0.01" id="catCommission" placeholder="مثال: 5"></div>
        <div class="form-group">
          <label for="catStatus">الحالة</label>
          <select id="catStatus">
            <option value="active">فعال</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>
      <div class="modal-footer">"""
content = re.sub(old_cat_body_pattern, new_cat_body, content, flags=re.DOTALL)


# Replace Javascript functions
js_replace_map = {
    r"async function uploadImageToSupabase\(file\)\{.*?return supabaseClient.storage.from\('products'\).getPublicUrl\(path\).data.publicUrl\}": 
    "async function uploadImageToSupabase(file, type){const bucket = type === 'category' ? 'category-images' : 'product-images';const path=`${Date.now()}_${sanitizeFileName(file.name)}`;const {error}=await supabaseClient.storage.from(bucket).upload(path,file,{upsert:true});if(error)throw error;return supabaseClient.storage.from(bucket).getPublicUrl(path).data.publicUrl}",

    r"async function handleImageSelection\(input,type\)\{.*?const url=await uploadImageToSupabase\(file\);.*?\}":
    "async function handleImageSelection(input,type){const file=input.files&&input.files[0];if(!file)return;try{uploadState[type].isUploading=true;setUploadStatus(type,'جاري رفع الصورة مباشرة إلى Supabase Storage...');const url=await uploadImageToSupabase(file, type);setImagePreview(type,url,`تم رفع ${file.name}`);setUploadStatus(type,'تم رفع الصورة بنجاح ويمكنك الآن الحفظ.');showToast('تم رفع الصورة بنجاح')}catch(err){setUploadStatus(type,`فشل رفع الصورة: ${err.message}`,true);showToast(`فشل رفع الصورة: ${err.message}`,'error')}finally{uploadState[type].isUploading=false}}",

    r"function resetCategoryForm\(\)\{.*?setUploadStatus\('category','يمكنك عرض الصورة الحالية أو رفع صورة جديدة مباشرة.'\)\}":
    "function resetCategoryForm(){document.getElementById('editCatId').value='';document.getElementById('catName').value='';document.getElementById('catDesc').value='';document.getElementById('catDisplayOrder').value='';document.getElementById('catCommission').value='';document.getElementById('catStatus').value='active';document.getElementById('catModalTitle').textContent='إضافة تصنيف جديد';document.getElementById('categoryImageFile').value='';setImagePreview('category','','معاينة الصورة');setUploadStatus('category','يمكنك عرض الصورة الحالية أو رفع صورة جديدة مباشرة.')}",

    r"function openCategoryModal\(id=''\)\{.*?openModal\('categoryModal'\)\}":
    "function openCategoryModal(id=''){resetCategoryForm();if(id){const c=categoriesCache.find(x=>String(x.id)===String(id));if(c){document.getElementById('editCatId').value=c.id;document.getElementById('catName').value=c.name||'';document.getElementById('catDesc').value=c.description||'';document.getElementById('catDisplayOrder').value=c.display_order||'';document.getElementById('catCommission').value=c.commission_percentage||'';document.getElementById('catStatus').value=c.status||'active';document.getElementById('catModalTitle').textContent='تعديل التصنيف';if(c.image_url){setImagePreview('category',c.image_url,'الصورة الحالية');setUploadStatus('category','توجد صورة حالية. يمكنك تغييرها في أي وقت.')}}}openModal('categoryModal')}",

    r"async function saveCategory\(\)\{.*?showToast\('تم حفظ التصنيف بنجاح'\)\}":
    "async function saveCategory(){const id=document.getElementById('editCatId').value,name=document.getElementById('catName').value.trim();if(!name){showToast('أدخل اسم التصنيف','error');return}const payload={name,description:document.getElementById('catDesc').value.trim(),display_order:parseInt(document.getElementById('catDisplayOrder').value)||0,commission_percentage:parseFloat(document.getElementById('catCommission').value)||0,status:document.getElementById('catStatus').value};if(uploadState.category.publicUrl)payload.image_url=uploadState.category.publicUrl;const {error}=id?await supabaseClient.from('categories').update(payload).eq('id',id):await supabaseClient.from('categories').insert([payload]);if(error){showToast(`فشل حفظ التصنيف: ${error.message}`,'error');return}closeModal('categoryModal');await loadCategories();showToast('تم حفظ التصنيف بنجاح')}",

    r"function resetProductForm\(\)\{.*?setUploadStatus\('product','اختر صورة وسيتم رفعها مباشرة إلى Supabase Storage.'\)\}":
    "function toggleOptionsSection(show){document.getElementById('prodOptionsSection').style.display=show?'block':'none'}\n    function addProdOption(name='', price=''){const div=document.createElement('div');div.className='form-group';div.style.display='flex';div.style.gap='8px';div.innerHTML=`<input type=\"text\" placeholder=\"اسم الخيار\" class=\"opt-name\" value=\"${escapeHtml(name)}\"><input type=\"number\" step=\"0.01\" placeholder=\"السعر ($)\" class=\"opt-price\" value=\"${price}\"><button type=\"button\" class=\"action-btn danger\" onclick=\"this.parentElement.remove()\"><i class=\"fa-solid fa-trash\"></i></button>`;document.getElementById('prodOptionsList').appendChild(div)}\n    function addProdRequiredField(key='', placeholder=''){const div=document.createElement('div');div.className='form-group';div.style.display='flex';div.style.gap='8px';div.innerHTML=`<input type=\"text\" placeholder=\"اسم الحقل (مثال: player_id)\" class=\"req-key\" value=\"${escapeHtml(key)}\"><input type=\"text\" placeholder=\"النص التوضيحي (مثال: اكتب ID اللاعب هنا)\" class=\"req-placeholder\" value=\"${escapeHtml(placeholder)}\"><button type=\"button\" class=\"action-btn danger\" onclick=\"this.parentElement.remove()\"><i class=\"fa-solid fa-trash\"></i></button>`;document.getElementById('prodRequiredFieldsList').appendChild(div)}\n    function resetProductForm(){document.getElementById('editProdId').value='';document.getElementById('prodName').value='';document.getElementById('prodShortDesc').value='';document.getElementById('prodDesc').value='';document.getElementById('prodPrice').value='';document.getElementById('prodDisplayOrder').value='';document.getElementById('prodStatus').value='active';document.getElementById('prodHasOptions').checked=false;toggleOptionsSection(false);document.getElementById('prodOptionsList').innerHTML='';document.getElementById('prodRequiredFieldsList').innerHTML='';document.getElementById('prodModalTitle').textContent='إضافة منتج جديد';document.getElementById('productImageFile').value='';ensureCategoryOptions();if(categoriesCache.length)document.getElementById('prodCategorySelect').value=categoriesCache[0].id;setImagePreview('product','','معاينة الصورة');setUploadStatus('product','اختر صورة وسيتم رفعها مباشرة إلى Supabase Storage.')}",

    r"function openProductModal\(id=''\)\{.*?openModal\('productModal'\)\}":
    "function openProductModal(id=''){resetProductForm();if(id){const p=productsCache.find(x=>String(x.id)===String(id));if(p){document.getElementById('editProdId').value=p.id;document.getElementById('prodName').value=p.name||'';document.getElementById('prodShortDesc').value=p.short_description||'';document.getElementById('prodDesc').value=p.description||'';document.getElementById('prodPrice').value=getDisplayPrice(p);document.getElementById('prodCategorySelect').value=p.category_id||'';document.getElementById('prodDisplayOrder').value=p.display_order||'';document.getElementById('prodStatus').value=p.status||'active';if(p.options&&p.options.length){document.getElementById('prodHasOptions').checked=true;toggleOptionsSection(true);p.options.forEach(opt=>addProdOption(opt.name,opt.price))}if(p.required_fields&&p.required_fields.length){p.required_fields.forEach(req=>addProdRequiredField(req.key,req.placeholder))}document.getElementById('prodModalTitle').textContent='تعديل المنتج';if(p.image_url){setImagePreview('product',p.image_url,'الصورة الحالية');setUploadStatus('product','توجد صورة حالية. يمكنك تغييرها ونسخ رابطها.')}}}openModal('productModal')}",

    r"async function saveProduct\(\)\{.*?showToast\('تم حفظ المنتج بنجاح'\)\}":
    "async function saveProduct(){const id=document.getElementById('editProdId').value,name=document.getElementById('prodName').value.trim(),price=parseFloat(document.getElementById('prodPrice').value),categoryId=document.getElementById('prodCategorySelect').value;if(!name){showToast('أدخل اسم المنتج','error');return}if(!categoryId){showToast('اختر تصنيفاً للمنتج','error');return}if(!Number.isFinite(price)||price<=0){showToast('أدخل سعراً صحيحاً','error');return}if(uploadState.product.isUploading){showToast('انتظر حتى يكتمل رفع الصورة','error');return}const options=[];if(document.getElementById('prodHasOptions').checked){document.querySelectorAll('#prodOptionsList > div').forEach(div=>{const n=div.querySelector('.opt-name').value.trim(),p=parseFloat(div.querySelector('.opt-price').value);if(n&&Number.isFinite(p))options.push({name:n,price:p})})}const required_fields=[];document.querySelectorAll('#prodRequiredFieldsList > div').forEach(div=>{const k=div.querySelector('.req-key').value.trim(),p=div.querySelector('.req-placeholder').value.trim();if(k)required_fields.push({key:k,placeholder:p})});let payload={name,category_id:categoryId,short_description:document.getElementById('prodShortDesc').value.trim(),description:document.getElementById('prodDesc').value.trim(),price_usd:price,display_order:parseInt(document.getElementById('prodDisplayOrder').value)||0,status:document.getElementById('prodStatus').value,options:options,required_fields:required_fields};if(uploadState.product.publicUrl)payload.image_url=uploadState.product.publicUrl;let result=id?await supabaseClient.from('products').update(payload).eq('id',id):await supabaseClient.from('products').insert([payload]);if(result.error&&String(result.error.message||'').toLowerCase().includes('price_usd')){payload.price=price;delete payload.price_usd;result=id?await supabaseClient.from('products').update(payload).eq('id',id):await supabaseClient.from('products').insert([payload])}if(result.error){showToast(`فشل حفظ المنتج: ${result.error.message}`,'error');return}closeModal('productModal');await loadProducts();showToast('تم حفظ المنتج بنجاح')}"
}

for pattern, repl in js_replace_map.items():
    content = re.sub(pattern, repl, content, flags=re.DOTALL)

with open('admin.html', 'w', encoding='utf-8') as f:
    f.write(content)

