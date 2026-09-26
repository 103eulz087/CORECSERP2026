using System;
using System.Collections.Generic;
using System.Drawing;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using DevExpress.XtraGrid.Views.Grid;
using System.ComponentModel;
using DevExpress.XtraGrid.Columns;
using DevExpress.XtraGrid;

namespace SalesInventorySystem.Classes
{
    class DevXGridViewSettings
    {
        // Keeps a SplitContainerControl's first panel at a fixed share of the container
        // (e.g. 0.55 = top grid 55%) on every resize, and remembers a new share when the
        // user drags the divider. Used by the Posted tabs (vouchers grid over details grid)
        // so the details grid stays visible on low-resolution monitors.
        // Plain FixedPanel.None proportional resizing isn't enough on its own: if the
        // control is laid out very small first (e.g. while being hosted), the second panel
        // gets squeezed to its minimum and the ratio is lost for good.
        public static void KeepSplitterRatio(DevExpress.XtraEditors.SplitContainerControl split, double firstPanelRatio)
        {
            const int minUsableSize = 200;   // ignore transient tiny layouts
            double ratio = firstPanelRatio;
            bool applying = false;

            int Length() => split.Horizontal ? split.Width : split.Height;

            void Apply()
            {
                if (Length() < minUsableSize) return;
                applying = true;
                try { split.SplitterPosition = (int)(Length() * ratio); }
                finally { applying = false; }
            }

            split.SizeChanged += (s, e) => Apply();
            split.SplitterMoved += (s, e) =>
            {
                if (applying || Length() < minUsableSize) return;
                ratio = (double)split.SplitterPosition / Length();
            };
            Apply();
        }

        public static GridView gridStrikeout(RowCellStyleEventArgs e,String col,String value)
        {
            GridView view = new GridView();
            //bool check = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, col));
            if (e.Column.FieldName == col)
            {
                if (Convert.ToString(e.CellValue) == value)
                {
                    e.Appearance.ForeColor = Color.Red;
                    e.Appearance.Font = new System.Drawing.Font(e.Appearance.Font, FontStyle.Strikeout);
                }
            }
            return view;
        }

       

        private static GridView rowcellstyle(object sender, DevExpress.XtraGrid.Views.Grid.RowCellStyleEventArgs e,string col,Color color)
        {
            
            GridView view = (GridView)sender;
            bool check = Convert.ToBoolean(view.GetRowCellValue(e.RowHandle, col));
            if (!check)
            {
                e.Appearance.Font = new System.Drawing.Font(e.Appearance.Font, FontStyle.Strikeout);
                e.Appearance.ForeColor = color;
            }
            return view;
        }
        public static GridView rowstyle(object sender, RowStyleEventArgs e,string viewcol,string viewvalue)
        {
            GridView View = sender as GridView;
            if (e.RowHandle >= 0)
            {
                string category = View.GetRowCellDisplayText(e.RowHandle, View.Columns[viewcol]);
                if (category.Equals(viewvalue))
                {
                    e.Appearance.BackColor = Color.Salmon;
                    e.Appearance.BackColor2 = Color.SeaShell;
                    e.HighPriority = true;
                }
            }
            return View;
        }

        private static GridView showeditor(object sender, CancelEventArgs e,string col)
        {
            GridView view = sender as GridView;
            if (view.FocusedColumn.FieldName != col)
                e.Cancel = true;
            return view;

        }

        public static GridView setGridFormat(object sender)
        {
            
            GridView view = sender as GridView;
            foreach (GridColumn col in view.Columns)
            {

                if (col.ColumnType == typeof(DateTime))
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    col.DisplayFormat.FormatString = "MM/dd/yyyy";
                }
                else
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                    col.DisplayFormat.FormatString = "n2";
                }
            }
            return view;
        }
       
        public static GridView getTotalSummation(object sender,params string[] summaryvalues)
        {
            GridView view = sender as GridView;
            
            foreach (GridColumn col in view.Columns)
            {
                //foreach (String str in values)
                //{
                //    view.Columns[str].Visible = false;
                //}

                if (col.ColumnType == typeof(DateTime))
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    col.DisplayFormat.FormatString = "MM/dd/yyyy";
                }
                else
                {
                    foreach (string str in summaryvalues)
                    {
                        if (str == col.FieldName)
                        {
                            col.Summary.Clear();
                            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, str, "{0:n2}");
                            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                            col.DisplayFormat.FormatString = "n2";
                        }
                    }
                }
            }
            return view;
        }
        public static GridView getTotalSummation(object sender, string[] hidevalues,params string[] summaryvalues)
        {
            GridView view = sender as GridView;

            foreach (GridColumn col in view.Columns)
            {
                foreach (String str2 in hidevalues)
                {
                    view.Columns[str2].Visible = false;
                }

                if (col.ColumnType == typeof(DateTime))
                {
                    col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.DateTime;
                    col.DisplayFormat.FormatString = "MM/dd/yyyy";
                }
                else
                {
                    foreach (string str in summaryvalues)
                    {
                        if (str == col.FieldName)
                        {
                            col.Summary.Clear();
                            col.Summary.Add(DevExpress.Data.SummaryItemType.Sum, str, "{0:n2}");
                            col.DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                            col.DisplayFormat.FormatString = "n2";
                        }
                    }
                }
            }
            return view;
        }

        public static void ShowFooterTotal(GridView view,string col)
        {
            if (view.Columns[col] == null) return;   // NEW - avoid NRE when a caller's result shape doesn't include this column

            // NEW - de-dup before adding. GridColumnSummaryItemCollection/
            // GridGroupSummaryItemCollection.Add() has no built-in de-dup, so
            // calling this a second time for the same column (e.g. every
            // LoadXxx()/Refresh a caller re-runs after rebinding) stacked a
            // duplicate Sum item each time -- the footer cell then showed the
            // same total repeated/growing on every refresh instead of once.
            view.Columns[col].Summary.Clear();
            for (int i = view.GroupSummary.Count - 1; i >= 0; i--)
            {
                if (view.GroupSummary[i].FieldName == col && view.GroupSummary[i].SummaryType == DevExpress.Data.SummaryItemType.Sum)
                    view.GroupSummary.RemoveAt(i);
            }

            GridGroupSummaryItem ite11 = new GridGroupSummaryItem();
            ite11.FieldName = col;
            ite11.SummaryType = DevExpress.Data.SummaryItemType.Sum;
            ite11.ShowInGroupColumnFooter = view.Columns[col];
            view.GroupSummary.Add(ite11);
            view.Columns[col].Summary.Add(DevExpress.Data.SummaryItemType.Sum, col, "{0:n2}");
            //return view;
        }

        // Sets DisplayFormat (numeric, "n2") on exactly the named columns' row
        // cells -- NOT the whole view (unlike setGridFormat above, which blindly
        // formats every non-DateTime column and would corrupt any text/lookup
        // column in a mixed grid). ShowFooterTotal only formats the footer sum;
        // per CLAUDE.md's "Reporting Quantity/Amount columns must be numeric"
        // convention, the row cells need this separately, or a report grid's
        // Debit/Credit/Amount columns render unformatted even though the
        // footer total looks right. Call once per view after binding (same
        // timing as ShowFooterTotal). Missing/absent columns are skipped, not
        // an error, so this is safe to call against a result shape that varies.
        public static void FormatNumericColumns(GridView view, params string[] columnNames)
        {
            foreach (var col in columnNames)
            {
                if (view.Columns[col] == null) continue;
                view.Columns[col].DisplayFormat.FormatType = DevExpress.Utils.FormatType.Numeric;
                view.Columns[col].DisplayFormat.FormatString = "n2";
            }
        }

        public static void ShowFooterCountTotal(GridView view, string col)
        {

            GridGroupSummaryItem ite11 = new GridGroupSummaryItem();
            ite11.FieldName = col;
            ite11.SummaryType = DevExpress.Data.SummaryItemType.Count;
            ite11.ShowInGroupColumnFooter = view.Columns[col];
            view.GroupSummary.Add(ite11);
            view.Columns[col].Summary.Add(DevExpress.Data.SummaryItemType.Count, col, "{0}");
            //return view;
        }

        // Standard "totals band" appearance for grid footers/group summaries -- Tahoma 9.75F
        // Bold, dark-brown text (102,60,0) on a warm cream band (255,244,214). Reference
        // implementation: POS/POSSalesReportDevEx.cs's SalesTransactionSummary tab (gridView1/
        // gridView2 constructor wiring). Call once per view (e.g. in the form's constructor or
        // Load, same as that reference) rather than copying the Font/Color literals into each
        // new module -- keeps every report/grid's totals band visually identical, and a future
        // palette change only needs to happen here. See CLAUDE.md's "Grid footer/totals band
        // styling" convention.
        public static void ApplyTotalsBandAppearance(GridView view)
        {
            Font font = new Font("Tahoma", 9.75F, FontStyle.Bold);
            Color foreColor = Color.FromArgb(102, 60, 0);
            Color backColor = Color.FromArgb(255, 244, 214);

            view.Appearance.FooterPanel.Font = font;
            view.Appearance.FooterPanel.ForeColor = foreColor;
            view.Appearance.FooterPanel.BackColor = backColor;
            view.Appearance.FooterPanel.Options.UseFont = true;
            view.Appearance.FooterPanel.Options.UseForeColor = true;
            view.Appearance.FooterPanel.Options.UseBackColor = true;

            view.Appearance.GroupFooter.Font = font;
            view.Appearance.GroupFooter.ForeColor = foreColor;
            view.Appearance.GroupFooter.BackColor = backColor;
            view.Appearance.GroupFooter.Options.UseFont = true;
            view.Appearance.GroupFooter.Options.UseForeColor = true;
            view.Appearance.GroupFooter.Options.UseBackColor = true;

            view.Appearance.GroupRow.Font = font;
            view.Appearance.GroupRow.ForeColor = foreColor;
            view.Appearance.GroupRow.BackColor = backColor;
            view.Appearance.GroupRow.Options.UseFont = true;
            view.Appearance.GroupRow.Options.UseForeColor = true;
            view.Appearance.GroupRow.Options.UseBackColor = true;
        }
        //private static GridView rowstyle(object sender, DevExpress.XtraGrid.Views.Grid.RowStyleEventArgs e,params string[] str,string highlightedcol)
        //{
        //    GridView view = sender as GridView;
        //    if (e.RowHandle >= 0)
        //    {
        //        string status = view.GetRowCellDisplayText(e.RowHandle, view.Columns["Status"]);
        //        if (status == "NO INVENTORY")
        //        {
        //            e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
        //            e.Appearance.BackColor = Color.Salmon;
        //            e.Appearance.BackColor2 = Color.SeaShell;
        //        }
        //        if (status == "FAILED")
        //        {
        //            e.Appearance.Font = new Font(e.Appearance.Font, FontStyle.Bold);
        //            e.Appearance.BackColor = Color.Blue;
        //            e.Appearance.BackColor2 = Color.LightBlue;
        //        }
        //    }
        //    return view;
        //}
    }
}
