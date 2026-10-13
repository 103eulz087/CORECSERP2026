using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;
using SalesInventorySystem.POSV2.Models;

namespace SalesInventorySystem.POSV2
{
    // Product search / picker for POS V2: the find box filters as you type; Enter or double-click picks.
    // Works on the terminal's local product copy, so it works offline.
    public sealed class PosProductSearchForm : XtraForm
    {
        private readonly GridControl _grid = new GridControl { Dock = DockStyle.Fill };
        private readonly GridView _view;
        private readonly List<PosProduct> _items;
        public PosProduct Picked { get; private set; }

        private PosProductSearchForm(IEnumerable<PosProduct> items, string title)
        {
            _items = items.ToList();
            Text = title;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(820, 520);
            MinimizeBox = false;
            ShowInTaskbar = false;
            KeyPreview = true;

            _view = new GridView(_grid);
            _grid.MainView = _view;
            _view.OptionsBehavior.Editable = false;
            _view.OptionsView.ShowGroupPanel = false;
            _view.OptionsFind.AlwaysVisible = true;
            _view.OptionsFind.FindDelay = 100;
            _view.OptionsSelection.EnableAppearanceFocusedCell = false;
            _view.Appearance.Row.Font = new Font("Tahoma", 11f);
            _grid.DataSource = _items.Select(p => new { p.ProductCode, p.Description, p.Barcode, Price = p.SellingPrice, VAT = p.IsVat }).ToList();
            _view.DoubleClick += (s, e) => { if (_view.CalcHitInfo(_grid.PointToClient(MousePosition)).InRow) Pick(); };
            Controls.Add(_grid);
            KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Enter) { Pick(); e.Handled = true; }
                else if (e.KeyCode == Keys.Escape) { DialogResult = DialogResult.Cancel; }
            };
            // columns exist only once the form is shown (PopulateColumns in the constructor creates none)
            Shown += (s, e) =>
            {
                _view.PopulateColumns();
                var price = _view.Columns["Price"];
                if (price != null)
                {
                    price.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    price.DisplayFormat.FormatString = "N2";
                    price.AppearanceCell.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    price.AppearanceCell.Options.UseTextOptions = true;
                    price.AppearanceHeader.TextOptions.HAlignment = DevExpress.Utils.HorzAlignment.Far;
                    price.AppearanceHeader.Options.UseTextOptions = true;
                }
                _view.BestFitColumns();
                _view.ShowFindPanel();
            };
        }

        private void Pick()
        {
            int h = _view.FocusedRowHandle;
            if (h < 0) return;
            string code = Convert.ToString(_view.GetRowCellValue(h, "ProductCode"));
            Picked = _items.FirstOrDefault(p => p.ProductCode == code);
            if (Picked != null) DialogResult = DialogResult.OK;
        }

        public static PosProduct Pick(IWin32Window owner, IEnumerable<PosProduct> items, string title)
        {
            using (var f = new PosProductSearchForm(items, title))
                return f.ShowDialog(owner) == DialogResult.OK ? f.Picked : null;
        }
    }
}
