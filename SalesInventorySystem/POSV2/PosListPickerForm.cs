using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Windows.Forms;
using DevExpress.XtraEditors;
using DevExpress.XtraGrid;
using DevExpress.XtraGrid.Views.Grid;

namespace SalesInventorySystem.POSV2
{
    // A small list picker for POS V2 (sales to void / reprint, held sales to recall). Enter or double-click picks.
    public sealed class PosListPickerForm : XtraForm
    {
        private readonly GridControl _grid = new GridControl { Dock = DockStyle.Fill };
        private readonly GridView _view;
        private int _picked = -1;

        private PosListPickerForm(string title, IList<object> rows)
        {
            Text = title;
            StartPosition = FormStartPosition.CenterParent;
            ClientSize = new Size(760, 440);
            MinimizeBox = false; ShowInTaskbar = false; KeyPreview = true;
            _view = new GridView(_grid);
            _grid.MainView = _view;
            _view.OptionsBehavior.Editable = false;
            _view.OptionsView.ShowGroupPanel = false;
            _view.OptionsFind.AlwaysVisible = true;
            _view.OptionsSelection.EnableAppearanceFocusedCell = false;
            _view.Appearance.Row.Font = new Font("Tahoma", 11f);
            // a DataTable from the projected rows' properties: the grid then always finds the columns
            var dt = new System.Data.DataTable();
            var props = rows.Count > 0 ? rows[0].GetType().GetProperties() : new System.Reflection.PropertyInfo[0];
            foreach (var p in props)
                dt.Columns.Add(p.Name, Nullable.GetUnderlyingType(p.PropertyType) ?? p.PropertyType);
            foreach (var r in rows)
                dt.Rows.Add(props.Select(p => p.GetValue(r, null) ?? (object)DBNull.Value).ToArray());
            _grid.DataSource = dt;
            _view.PopulateColumns();
            foreach (DevExpress.XtraGrid.Columns.GridColumn c in _view.Columns)
                if (c.ColumnType == typeof(decimal))
                {
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    c.DisplayFormat.FormatString = "N2";
                }
                else if (c.ColumnType == typeof(DateTime))
                {
                    c.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    c.DisplayFormat.FormatString = "yyyy-MM-dd HH:mm";
                }
            _view.BestFitColumns();
            _view.DoubleClick += (s, e) => { if (_view.CalcHitInfo(_grid.PointToClient(MousePosition)).InRow) Pick(); };
            Controls.Add(_grid);
            KeyDown += (s, e) =>
            {
                if (e.KeyCode == Keys.Enter) { Pick(); e.Handled = true; }
                else if (e.KeyCode == Keys.Escape) DialogResult = DialogResult.Cancel;
            };
        }

        private void Pick()
        {
            int h = _view.FocusedRowHandle;
            if (h < 0) return;
            _picked = _view.GetDataSourceRowIndex(h);
            DialogResult = DialogResult.OK;
        }

        // Shows the rows (as projected for display) and returns the picked item, or default when cancelled.
        public static T Pick<T>(IWin32Window owner, string title, IList<T> items, Func<T, object> show) where T : class
        {
            if (items.Count == 0) { XtraMessageBox.Show("Nothing to show."); return null; }
            var rows = items.Select(show).ToList();
            using (var f = new PosListPickerForm(title, rows))
                return f.ShowDialog(owner) == DialogResult.OK && f._picked >= 0 && f._picked < items.Count ? items[f._picked] : null;
        }
    }
}
