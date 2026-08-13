using System.Threading.Tasks;

namespace SalesInventorySystem.Classes
{
    public interface IResettableForm
    {
        /// <summary>
        /// Clears data grids, resets inputs to default state, and fetches new IDs if necessary.
        /// </summary>
        Task ResetUIAsync();
    }
}