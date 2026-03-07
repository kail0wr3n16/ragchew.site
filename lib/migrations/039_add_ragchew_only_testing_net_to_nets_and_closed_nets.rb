class AddRagchewOnlyTestingNetToNetsAndClosedNets < ActiveRecord::Migration[7.2]
  def change
    add_column :nets, :ragchew_only_testing_net, :boolean, null: false, default: false
    add_column :closed_nets, :ragchew_only_testing_net, :boolean, null: false, default: false
  end
end
