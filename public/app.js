const { createClient } = supabase;
const isConfigured =
  window.INVENTORY_CONFIG &&
  window.INVENTORY_CONFIG.supabaseUrl &&
  window.INVENTORY_CONFIG.supabasePublishableKey &&
  !window.INVENTORY_CONFIG.supabaseUrl.includes("TU-PROYECTO");

const state = { products: [], movements: [], user: null };
const elements = {
  addProductButton: document.querySelector("#add-product-button"),
  adjustmentHelp: document.querySelector("#adjustment-help"),
  appContent: document.querySelector("#app-content"),
  authEmail: document.querySelector("#auth-email"),
  authError: document.querySelector("#auth-error"),
  authForm: document.querySelector("#auth-form"),
  authPassword: document.querySelector("#auth-password"),
  authScreen: document.querySelector("#auth-screen"),
  categoryFilter: document.querySelector("#category-filter"),
  exportButton: document.querySelector("#export-button"),
  initialStockField: document.querySelector("#initial-stock-field"),
  loadingScreen: document.querySelector("#loading-screen"),
  lowStockCount: document.querySelector("#low-stock-count"),
  movementDialog: document.querySelector("#movement-dialog"),
  movementDialogTitle: document.querySelector("#movement-dialog-title"),
  movementEmptyState: document.querySelector("#movement-empty-state"),
  movementForm: document.querySelector("#movement-form"),
  movementFormError: document.querySelector("#movement-form-error"),
  movementNote: document.querySelector("#movement-note"),
  movementProductId: document.querySelector("#movement-product-id"),
  movementQuantity: document.querySelector("#movement-quantity"),
  movementTableBody: document.querySelector("#movement-table-body"),
  movementType: document.querySelector("#movement-type"),
  productCategory: document.querySelector("#product-category"),
  productCode: document.querySelector("#product-code"),
  productCount: document.querySelector("#product-count"),
  productDescription: document.querySelector("#product-description"),
  productDialog: document.querySelector("#product-dialog"),
  productDialogTitle: document.querySelector("#product-dialog-title"),
  productEmptyState: document.querySelector("#product-empty-state"),
  productForm: document.querySelector("#product-form"),
  productFormError: document.querySelector("#product-form-error"),
  productId: document.querySelector("#product-id"),
  productInitialStock: document.querySelector("#product-initial-stock"),
  productMinStock: document.querySelector("#product-min-stock"),
  productName: document.querySelector("#product-name"),
  productPurchasePrice: document.querySelector("#product-purchase-price"),
  productSalePrice: document.querySelector("#product-sale-price"),
  productTableBody: document.querySelector("#product-table-body"),
  purchaseValue: document.querySelector("#purchase-value"),
  searchInput: document.querySelector("#search-input"),
  signOutButton: document.querySelector("#sign-out-button"),
  unitCount: document.querySelector("#unit-count"),
  userEmail: document.querySelector("#user-email"),
};

let db = null;

function formatMoney(value) {
  return new Intl.NumberFormat("es-BO", {
    style: "currency",
    currency: "BOB",
    minimumFractionDigits: 2,
  }).format(value);
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function showScreen(screen) {
  elements.loadingScreen.hidden = screen !== "loading";
  elements.authScreen.hidden = screen !== "auth";
  elements.appContent.hidden = screen !== "app";
}

function showError(target, message) {
  target.textContent = message || "";
}

function getProduct(productId) {
  return state.products.find((product) => product.id === productId);
}

function mapProduct(product) {
  return {
    id: product.id,
    name: product.name,
    code: product.code,
    category: product.category || "",
    description: product.description || "",
    quantity: Number(product.quantity),
    minStock: Number(product.min_stock),
    purchasePrice: Number(product.purchase_price),
    salePrice: Number(product.sale_price),
  };
}

function mapMovement(movement) {
  return {
    id: movement.id,
    productId: movement.product_id,
    productName: movement.product_name,
    type: movement.type,
    quantity: Number(movement.quantity),
    note: movement.note || "",
    createdAt: movement.created_at,
  };
}

async function loadInventory() {
  const [productsResult, movementsResult] = await Promise.all([
    db.from("products").select("*").eq("owner_id", state.user.id).order("name"),
    db.from("movements").select("*").eq("owner_id", state.user.id).order("created_at", { ascending: false }).limit(20),
  ]);

  if (productsResult.error) throw productsResult.error;
  if (movementsResult.error) throw movementsResult.error;

  state.products = productsResult.data.map(mapProduct);
  state.movements = movementsResult.data.map(mapMovement);
  render();
}

function render() {
  renderStats();
  renderCategories();
  renderProducts();
  renderMovements();
}

function renderStats() {
  const units = state.products.reduce((total, product) => total + product.quantity, 0);
  const purchaseValue = state.products.reduce(
    (total, product) => total + product.quantity * product.purchasePrice,
    0,
  );
  const lowStock = state.products.filter((product) => product.quantity <= product.minStock).length;

  elements.productCount.textContent = state.products.length;
  elements.unitCount.textContent = units;
  elements.purchaseValue.textContent = formatMoney(purchaseValue);
  elements.lowStockCount.textContent = lowStock;
}

function renderCategories() {
  const selected = elements.categoryFilter.value;
  const categories = [...new Set(state.products.map((product) => product.category).filter(Boolean))].sort();
  elements.categoryFilter.innerHTML =
    '<option value="">Todas</option>' +
    categories.map((category) => `<option value="${escapeHtml(category)}">${escapeHtml(category)}</option>`).join("");
  elements.categoryFilter.value = categories.includes(selected) ? selected : "";
}

function renderProducts() {
  const search = elements.searchInput.value.trim().toLocaleLowerCase("es");
  const category = elements.categoryFilter.value;
  const products = state.products.filter((product) => {
    const matchesSearch =
      !search ||
      product.name.toLocaleLowerCase("es").includes(search) ||
      product.code.toLocaleLowerCase("es").includes(search);
    return matchesSearch && (!category || product.category === category);
  });

  elements.productTableBody.innerHTML = products
    .map((product) => {
      const lowStock = product.quantity <= product.minStock;
      return `
        <tr>
          <td>
            <span class="product-name">${escapeHtml(product.name)}</span>
            <span class="product-description">${escapeHtml(product.description || "Sin descripcion")}</span>
          </td>
          <td>${escapeHtml(product.code)}</td>
          <td>${escapeHtml(product.category || "Sin categoria")}</td>
          <td><span class="stock-badge ${lowStock ? "stock-low" : "stock-ok"}">${product.quantity}</span></td>
          <td>${formatMoney(product.purchasePrice)}</td>
          <td>${formatMoney(product.salePrice)}</td>
          <td>
            <div class="actions">
              <button class="button secondary" type="button" data-action="movement" data-id="${product.id}">Movimiento</button>
              <button class="button secondary" type="button" data-action="edit" data-id="${product.id}">Editar</button>
              <button class="button danger" type="button" data-action="delete" data-id="${product.id}">Eliminar</button>
            </div>
          </td>
        </tr>
      `;
    })
    .join("");
  elements.productEmptyState.hidden = products.length > 0;
}

function renderMovements() {
  const labels = { entry: "Entrada", exit: "Salida", adjustment: "Ajuste", initial: "Inicial" };

  elements.movementTableBody.innerHTML = state.movements
    .map(
      (movement) => `
        <tr>
          <td>${new Intl.DateTimeFormat("es-BO", { dateStyle: "short", timeStyle: "short" }).format(new Date(movement.createdAt))}</td>
          <td>${escapeHtml(movement.productName)}</td>
          <td><span class="movement-badge ${movement.type === "initial" ? "adjustment" : movement.type}">${labels[movement.type]}</span></td>
          <td>${movement.quantity > 0 ? "+" : ""}${movement.quantity}</td>
          <td>${escapeHtml(movement.note || "-")}</td>
        </tr>
      `,
    )
    .join("");
  elements.movementEmptyState.hidden = state.movements.length > 0;
}

function openNewProductDialog() {
  elements.productForm.reset();
  elements.productId.value = "";
  elements.productDialogTitle.textContent = "Nuevo producto";
  showError(elements.productFormError);
  elements.initialStockField.hidden = false;
  elements.productDialog.showModal();
}

function openEditProductDialog(productId) {
  const product = getProduct(productId);
  if (!product) return;

  elements.productForm.reset();
  elements.productId.value = product.id;
  elements.productName.value = product.name;
  elements.productCode.value = product.code;
  elements.productCategory.value = product.category;
  elements.productDescription.value = product.description;
  elements.productMinStock.value = product.minStock;
  elements.productPurchasePrice.value = product.purchasePrice;
  elements.productSalePrice.value = product.salePrice;
  elements.productDialogTitle.textContent = "Editar producto";
  showError(elements.productFormError);
  elements.initialStockField.hidden = true;
  elements.productDialog.showModal();
}

async function handleProductSubmit(event) {
  event.preventDefault();
  showError(elements.productFormError);

  const id = elements.productId.value;
  const values = {
    name: elements.productName.value.trim(),
    code: elements.productCode.value.trim(),
    category: elements.productCategory.value.trim(),
    description: elements.productDescription.value.trim(),
    min_stock: Number(elements.productMinStock.value),
    purchase_price: Number(elements.productPurchasePrice.value),
    sale_price: Number(elements.productSalePrice.value),
  };

  try {
    if (id) {
      const { error } = await db.from("products").update(values).eq("id", id);
      if (error) throw error;
    } else {
      const initialStock = Number(elements.productInitialStock.value);
      const { error } = await db.rpc("create_inventory_product", {
        p_name: values.name,
        p_code: values.code,
        p_category: values.category,
        p_description: values.description,
        p_min_stock: values.min_stock,
        p_purchase_price: values.purchase_price,
        p_sale_price: values.sale_price,
        p_initial_stock: initialStock,
      });
      if (error) throw error;
    }

    elements.productDialog.close();
    await loadInventory();
  } catch (error) {
    const message = error.code === "23505" ? "Ya existe un producto con ese codigo." : error.message;
    showError(elements.productFormError, message);
  }
}

function openMovementDialog(productId) {
  const product = getProduct(productId);
  if (!product) return;

  elements.movementForm.reset();
  elements.movementProductId.value = product.id;
  elements.movementDialogTitle.textContent = `Movimiento: ${product.name}`;
  showError(elements.movementFormError);
  updateAdjustmentHelp();
  elements.movementDialog.showModal();
}

function updateAdjustmentHelp() {
  const isAdjustment = elements.movementType.value === "adjustment";
  elements.movementQuantity.min = isAdjustment ? "0" : "1";
  elements.adjustmentHelp.textContent = isAdjustment
    ? "En un ajuste, la cantidad indicada reemplazara las existencias actuales."
    : "";
}

async function handleMovementSubmit(event) {
  event.preventDefault();
  showError(elements.movementFormError);

  try {
    const { error } = await db.rpc("register_inventory_movement", {
      p_product_id: elements.movementProductId.value,
      p_type: elements.movementType.value,
      p_quantity: Number(elements.movementQuantity.value),
      p_note: elements.movementNote.value.trim(),
    });
    if (error) throw error;

    elements.movementDialog.close();
    await loadInventory();
  } catch (error) {
    showError(elements.movementFormError, error.message);
  }
}

async function deleteProduct(productId) {
  const product = getProduct(productId);
  if (!product || !confirm(`Eliminar "${product.name}"? Su historial permanecera visible.`)) return;

  const { error } = await db.from("products").delete().eq("id", productId);
  if (error) {
    alert(error.message);
    return;
  }
  await loadInventory();
}

function exportCsv() {
  const headings = ["Nombre", "Codigo", "Categoria", "Caracteristicas", "Cantidad", "Stock minimo", "Precio compra", "Precio venta"];
  const values = state.products.map((product) => [
    product.name,
    product.code,
    product.category,
    product.description,
    product.quantity,
    product.minStock,
    product.purchasePrice,
    product.salePrice,
  ]);
  const csv = [headings, ...values]
    .map((row) => row.map((value) => `"${String(value).replaceAll('"', '""')}"`).join(","))
    .join("\n");
  const link = document.createElement("a");
  link.href = URL.createObjectURL(new Blob([`\uFEFF${csv}`], { type: "text/csv;charset=utf-8" }));
  link.download = "inventario.csv";
  link.click();
  URL.revokeObjectURL(link.href);
}

async function handleSignIn(event) {
  event.preventDefault();
  showError(elements.authError);

  const { error } = await db.auth.signInWithPassword({
    email: elements.authEmail.value.trim(),
    password: elements.authPassword.value,
  });

  if (error) showError(elements.authError, "No se pudo iniciar sesion. Revisa el correo y la contrasena.");
}

async function handleAuthChange(session) {
  state.user = session?.user || null;
  if (!state.user) {
    showScreen("auth");
    return;
  }

  showScreen("loading");
  elements.userEmail.textContent = state.user.email;
  try {
    await loadInventory();
    showScreen("app");
  } catch (error) {
    showScreen("auth");
    showError(elements.authError, `No se pudo cargar el inventario: ${error.message}`);
  }
}

async function initialize() {
  if (!isConfigured) {
    showScreen("auth");
    showError(elements.authError, "Falta configurar Supabase. Revisa el archivo config.js.");
    return;
  }

  db = createClient(window.INVENTORY_CONFIG.supabaseUrl, window.INVENTORY_CONFIG.supabasePublishableKey);
  db.auth.onAuthStateChange((_event, session) => {
    setTimeout(() => handleAuthChange(session), 0);
  });
  const { data } = await db.auth.getSession();
  await handleAuthChange(data.session);
}

elements.addProductButton.addEventListener("click", openNewProductDialog);
elements.authForm.addEventListener("submit", handleSignIn);
elements.productForm.addEventListener("submit", handleProductSubmit);
elements.movementForm.addEventListener("submit", handleMovementSubmit);
elements.movementType.addEventListener("change", updateAdjustmentHelp);
elements.exportButton.addEventListener("click", exportCsv);
elements.searchInput.addEventListener("input", renderProducts);
elements.categoryFilter.addEventListener("change", renderProducts);
elements.signOutButton.addEventListener("click", () => db.auth.signOut());
elements.productTableBody.addEventListener("click", (event) => {
  const button = event.target.closest("[data-action]");
  if (!button) return;
  if (button.dataset.action === "edit") openEditProductDialog(button.dataset.id);
  if (button.dataset.action === "movement") openMovementDialog(button.dataset.id);
  if (button.dataset.action === "delete") deleteProduct(button.dataset.id);
});
document.querySelectorAll("[data-close-dialog]").forEach((button) => {
  button.addEventListener("click", () => document.querySelector(`#${button.dataset.closeDialog}`).close());
});

initialize();
