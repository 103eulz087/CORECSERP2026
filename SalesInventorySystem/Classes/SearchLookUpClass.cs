using DevExpress.XtraEditors;
using DevExpress.XtraEditors.Repository;
using DevExpress.XtraGrid.Views.Grid;
using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SalesInventorySystem
{
    public class SearchLookUpClass
    {
        // 2026-10-15 (hardening H6, script-less C# change): the value of another column of the row the user PICKED.
        //
        // Before, both overloads read the popup grid's FocusedRowHandle. That row is the picked one only right after the
        // user clicked it. Proved against the v26.1 control in a harness on 2026-10-15 (docs/CLAUDE_WORKLOG.md, H6):
        //   - EditValue set in code with nothing picked yet (every Edit / Copy flow pre-fills its lookups that way):
        //     the old helper returned NULL, so the screen had no key (a crash or an empty parameter);
        //   - EditValue set in code after a pick: it returned the PREVIOUSLY picked row, another record's key;
        //   - a ValueMember that isn't unique (a name): the row behind the value is ambiguous (988 customers share
        //     a name on PRODUCTION), which is why posting screens now key their lookups on the record's key.
        //
        // Now: nothing picked -> null (never a row by accident); the popup's focused row when it is the row behind
        // EditValue (so a pick among duplicate names still returns the clicked row); otherwise the row behind
        // EditValue (GetSelectedDataRow: the first match when the ValueMember isn't unique, which is why posting
        // screens key their lookups on the record's key, not its name).
        public static Object getSingleValue(SearchLookUpEdit searchLookUpEdit1, string fieldname, SqlConnection con)
        {
            return getSingleValue(searchLookUpEdit1, fieldname);
        }

        public static Object getSingleValue(SearchLookUpEdit searchLookUpEdit1, string fieldname)
        {
            if (searchLookUpEdit1 == null || string.IsNullOrEmpty(fieldname)) return null;

            object editValue = searchLookUpEdit1.EditValue;
            if (editValue == null || editValue == DBNull.Value) return null;

            GridView view = searchLookUpEdit1.Properties.View;
            string valueMember = searchLookUpEdit1.Properties.ValueMember;

            // 1. the row the user clicked in the popup, when it is the row behind the current EditValue
            if (view != null && !string.IsNullOrEmpty(valueMember))
            {
                int rowHandle = view.FocusedRowHandle;
                if (view.IsDataRow(rowHandle))
                {
                    object focusedKey = view.GetRowCellValue(rowHandle, valueMember);
                    if (SameKey(focusedKey, editValue))
                        return view.GetRowCellValue(rowHandle, fieldname);
                }
            }

            // 2. the row behind EditValue (bound DataTable)
            if (searchLookUpEdit1.GetSelectedDataRow() is DataRowView drv)
                return drv.Row.Table.Columns.Contains(fieldname) ? drv[fieldname] : null;

            // 3. any other data source: the first row of the popup grid whose ValueMember equals EditValue
            if (view != null && !string.IsNullOrEmpty(valueMember))
            {
                for (int i = 0; i < view.DataRowCount; i++)
                    if (SameKey(view.GetRowCellValue(i, valueMember), editValue))
                        return view.GetRowCellValue(i, fieldname);
            }

            return null;
        }

        private static bool SameKey(object rowKey, object editValue)
        {
            if (rowKey == null || rowKey == DBNull.Value) return false;
            if (Equals(rowKey, editValue)) return true;
            return string.Equals(Convert.ToString(rowKey).Trim(), Convert.ToString(editValue).Trim(), StringComparison.Ordinal);
        }

        public static object GetSingleValueLookUpEdit(LookUpEdit lookupEdit, string fieldName)
        {
            DataRowView row = lookupEdit.GetSelectedDataRow() as DataRowView;
            return row?[fieldName];
        }


        // Grid-cell lookups: the repository item's view is the one shown for the cell being edited, so its focused
        // row is the picked row. Unchanged on 2026-10-15; callers get the cell's own EditValue for the key.
        public static object GetSingleValueRepositoryItem(
            RepositoryItemSearchLookUpEdit repoItem,
            string fieldName)
        {
            if (repoItem == null)
                throw new ArgumentNullException(nameof(repoItem));

            // The repository item itself exposes the view
            GridView view = repoItem.View as GridView;
            if (view == null)
                return null;

            // Validate column exists
            var col = view.Columns[fieldName];
            if (col == null)
                return null;

            int rowHandle = view.FocusedRowHandle;
            if (!view.IsDataRow(rowHandle))
                return null;

            return view.GetRowCellValue(rowHandle, col);
        }
    }
}
