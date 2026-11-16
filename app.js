// ServBookshop demo storefront. Add Supabase project URL and anon key here when ready.
const SUPABASE_URL = ""; const SUPABASE_ANON_KEY = "";
const WHATSAPP_NUMBER = ""; // international format, digits only, e.g. 249XXXXXXXXX
const products = [
{id:1,name:"The Art of Reading",ar:"فن القراءة",category:"Books",price:14.5,icon:"▤"},
{id:2,name:"Everyday English",ar:"الإنجليزية اليومية",category:"Books",price:12,icon:"A"},
{id:3,name:"Creative Notebook",ar:"دفتر إبداعي",category:"Stationery",price:5.5,icon:"✎"},
{id:4,name:"Study Essentials Set",ar:"مجموعة الدراسة",category:"School",price:9.75,icon:"✿"},
{id:5,name:"Stories for Curious Minds",ar:"قصص للعقول الشغوفة",category:"Books",price:16,icon:"❧"},
{id:6,name:"Colour Pencil Set",ar:"أقلام تلوين",category:"Stationery",price:7.25,icon:"✦"},
{id:7,name:"School Backpack",ar:"حقيبة مدرسية",category:"School",price:22,icon:"▱"},
{id:8,name:"Daily Planner",ar:"مخطط يومي",category:"Stationery",price:8,icon:"▦"}
];
let cart=[];let category="All";let language="en";let discount=0;
const THEME_KEY="servbookshop-theme";
function setTheme(theme){
  document.documentElement.dataset.theme=theme;
  const dark=theme==="dark";
  const button=$("#themeBtn");
  if(button){
    button.innerHTML=dark?"☼ <span data-en=\"Light\" data-ar=\"فاتح\">Light</span>":"◐ <span data-en=\"Dark\" data-ar=\"داكن\">Dark</span>";
    button.setAttribute("aria-label",dark?"Switch to light mode":"Switch to dark mode");
    button.title=dark?"Switch to light mode":"Switch to dark mode";
  }
  try{localStorage.setItem(THEME_KEY,theme)}catch(_){}
}

const $=s=>document.querySelector(s);
function t(en,ar){return language==="ar"?ar:en}
function renderProducts(){const q=$("#search").value.toLowerCase();$("#products").innerHTML=products.filter(p=>(category==="All"||p.category===category)&&(p.name.toLowerCase().includes(q)||p.ar.includes(q))).map(p=>`<article class="product"><div class="product-art"><span>${p.icon}</span></div><small>${p.category}</small><h3>${language==="ar"?p.ar:p.name}</h3><div class="product-bottom"><b>$${p.price.toFixed(2)}</b><button class="add" aria-label="Add ${p.name}" data-add="${p.id}">+</button></div></article>`).join("")||'<p>No products found.</p>'}
function toast(s){$("#toast").textContent=s;$("#toast").classList.add("show");setTimeout(()=>$("#toast").classList.remove("show"),2200)}
function renderCart(){const count=cart.reduce((n,x)=>n+x.qty,0),subtotal=cart.reduce((n,x)=>n+x.price*x.qty,0);$("#cartCount").textContent=count;$("#cartItems").innerHTML=cart.map(x=>`<div class="cart-line"><span>${language==="ar"?x.ar:x.name} × ${x.qty}</span><b>$${(x.price*x.qty).toFixed(2)}</b></div>`).join("")||'<p class="hint">Your cart is empty.</p>';$("#cartTotal").textContent="$"+(subtotal*(1-discount)).toFixed(2)}
document.addEventListener("click",e=>{const b=e.target.closest("[data-add]");if(b){const p=products.find(x=>x.id===Number(b.dataset.add)),old=cart.find(x=>x.id===p.id);old?old.qty++:cart.push({...p,qty:1});renderCart();toast(t("Added to cart","أُضيف إلى السلة"))}const f=e.target.closest("[data-category]");if(f){category=f.dataset.category;document.querySelectorAll(".filter").forEach(x=>x.classList.toggle("active",x===f));renderProducts()}});
$("#search").addEventListener("input",renderProducts);
$("#themeBtn").onclick=()=>setTheme(document.documentElement.dataset.theme==="dark"?"light":"dark");
$("#langBtn").onclick=()=>{language=language==="en"?"ar":"en";document.documentElement.lang=language;document.documentElement.dir=language==="ar"?"rtl":"ltr";document.querySelectorAll("[data-en]").forEach(el=>el.textContent=el.dataset[language]);$("#langBtn").textContent=language==="ar"?"English":"العربية";$("#search").placeholder=t("Search books and supplies","ابحث عن الكتب والمستلزمات");$("#orderNumber").placeholder=t("Order number","رقم الطلب");$("#coupon").placeholder=t("Discount code","رمز الخصم");renderProducts();renderCart()};
$("#cartBtn").onclick=()=>$("#cartPanel").classList.add("open");$("#closeCart").onclick=()=>$("#cartPanel").classList.remove("open");
$("#applyCoupon").onclick=()=>{const c=$("#coupon").value.trim().toUpperCase();if(c==="WELCOME10"){discount=.1;renderCart();toast(t("10% discount applied","تم تطبيق خصم ١٠٪"))}else toast(t("Invalid demo code. Try WELCOME10","رمز غير صالح. جرّب WELCOME10"))};
$("#checkout").onclick=()=>{if(!cart.length){toast(t("Your cart is empty","السلة فارغة"));return}const lines=cart.map(x=>`${x.name} x${x.qty} - $${(x.price*x.qty).toFixed(2)}`).join("\n");const msg=encodeURIComponent("Hello ServBookshop, I would like to order:\n"+lines+"\nTotal: "+$("#cartTotal").textContent);if(!WHATSAPP_NUMBER){toast(t("WhatsApp setup needed: add your shop number in app.js","يلزم إضافة رقم واتساب المتجر في app.js"));return}window.open("https://wa.me/"+WHATSAPP_NUMBER+"?text="+msg,"_blank")};
$("#trackForm").onsubmit=e=>{e.preventDefault();$("#trackResult").textContent=t("Demo only: order tracking will activate after Supabase is connected.","نسخة تجريبية: سيتم تفعيل تتبع الطلب بعد ربط Supabase.")};
$("#year").textContent=new Date().getFullYear();
let savedTheme="light";try{savedTheme=localStorage.getItem(THEME_KEY)||"light"}catch(_){}
setTheme(savedTheme==="dark"?"dark":"light");
renderProducts();renderCart();
// Supabase client is intentionally not initialized until project credentials are supplied.
